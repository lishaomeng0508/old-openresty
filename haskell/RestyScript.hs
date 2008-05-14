module RestyScript (
    SqlVal(..),
    readView
) where

import Text.ParserCombinators.Parsec
import Data.List (intercalate)

data VarContext = SymbolContext | LiteralContext
                deriving (Ord, Eq, Show)

data SqlVal = Select [SqlVal]
            | From [SqlVal]
            | Where SqlVal
            | Column SqlVal
            | Model SqlVal
            | Symbol String
            | QualifiedColumn (SqlVal, SqlVal)
            | Integer Integer
            | Float Float
            | String String
            | Variable (VarContext, String)
            | FuncCall (String, [SqlVal])
            | RelExpr (String, SqlVal, SqlVal)
            | OrExpr [SqlVal]
            | AndExpr [SqlVal]
            | NullClause
                deriving (Ord, Eq, Show)

{- instance Show SqlVal where show = showVal -}

quote :: Char -> String -> String
quote sep s = [sep] ++ quoteChars s ++ [sep]
              where quoteChars (x:xs) =
                        if x== sep
                            then sep : quoteChars xs
                            else x : quoteChars xs
                    quoteChars [] = ""

quoteLiteral :: String -> String
quoteLiteral = quote '\''

quoteIdent :: String -> String
quoteIdent = quote '"'

emitSql :: SqlVal -> String
emitSql (String s) = quoteLiteral s
emitSql (Select cols) = "select " ++ (intercalate ", " $ map emitSql cols)
emitSql (From models) = "from " ++ (intercalate ", " $ map emitSql models)
emitSql (Where cond) = "where " ++ (emitSql cond)
emitSql (Model model) = emitSql model
emitSql (Column col) = emitSql col
emitSql (Symbol name) = quoteIdent name
emitSql (OrExpr args) = "(" ++ (intercalate " or " $ map emitSql args) ++ ")"
emitSql (AndExpr args) = "(" ++ (intercalate " and " $ map emitSql args) ++ ")"
emitSql (RelExpr (op, lhs, rhs)) = "(" ++ (emitSql lhs) ++ op ++ (emitSql rhs) ++ ")"
emitSql (NullClause) = ""

readView :: String -> String -> Either String [String]
readView file input = case parse parseView file input of
                        Left err -> Left $ show err
                        Right vals -> Right [dump show vals, dump emitSql vals]
                        where dump f lst = unwords $ map f lst

parseView :: Parser [SqlVal]
parseView = do select <- parseSelect
               spaces
               from <- parseFrom
               spaces
               whereClause <- parseWhere
               return $ filter (\x->x /= NullClause)
                            [select, from, whereClause]

{-
          <|> parseWhere
          <|> parseLimit
          <|> parseLimit
          <|> parseOffset
          <|> parseGroupBy
          <|> parseOrderBy
          <?> "SQL clause"
-}

parseFrom :: Parser SqlVal
parseFrom = do string "from" >> many1 space
               models <- sepBy1 parseModel listSep
               return $ From models
        <|> (return $ NullClause)
        <?> "from clause"

parseModel :: Parser SqlVal
parseModel = do model <- symbol
                return $ Model $ Symbol model

symbol :: Parser String
symbol = do x <- letter
            xs <- many alphaNum
            return (x:xs)

listSep :: Parser ()
listSep = opSep ","

parseSelect :: Parser SqlVal
parseSelect = do string "select" >> many1 space
                 cols <- sepBy1 parseColumn listSep
                 return $ Select cols
          <?> "select clause"

parseColumn :: Parser SqlVal
parseColumn = do column <- symbol
                 return $ Column $ Symbol column
          <?> "selected column"

parseWhere :: Parser SqlVal
parseWhere = do string "where" >> many1 space
                cond <- parseOr
                return $ Where cond
         <|> (return $ NullClause)
         <?> "where clause"

parseOr :: Parser SqlVal
parseOr = do args <- sepBy1 parseAnd (opSep "or")
             return $ OrExpr args

opSep :: String -> Parser ()
opSep op = try(spaces >> string op) >> spaces

parseAnd :: Parser SqlVal
parseAnd = do args <- sepBy1 parseRel (opSep "and")
              return $ AndExpr args

parseRel :: Parser SqlVal
parseRel = do lhs <- parseColumn
              spaces
              op <- relOp
              spaces
              rhs <- parseColumn
              return $ RelExpr (op, lhs, rhs)

relOp :: Parser String
relOp = string "="
         <|> try (string ">=")
         <|> string ">"
         <|> try (string "<=")
         <|> string "<"
         <|> string "like"
