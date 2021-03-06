#!/usr/bin/env perl
# vi:filetype=

use strict;
use warnings;

use IPC::Run3;
use Test::Base 'no_plan';
#use Test::LongString;

run {
    my $block = shift;
    my $desc = $block->description;
    my ($stdout, $stderr);
    my $stdin = $block->in;
    run3 [qw< bin/restyscript view ast rs >], \$stdin, \$stdout, \$stderr;
    if (defined $block->error) {
        is $? >> 8, 1, "compiler returns 0 - $desc";
    } else {
        is $? >> 8, 0, "compiler returns 0 - $desc";
    }
    if (defined $block->error && $stderr) {
        $stderr =~ s/^expecting .*\n//ms;
        is $stderr, $block->error, "expected error msg - $desc";
        return;
    } elsif ($stderr) {
        warn $stderr
    }
    my @ln = split /\n+/, $stdout;
    my $ast = $block->ast;
    if (defined $ast) {
        $ln[0] =~ s/"view" \(line (\d+), column (\d+)\)/($1,$2)/gs;
        is "$ln[0]\n", $ast, "AST ok - $desc";
    }
    my $out = $block->out;
    is "$ln[1]\n", $out, "Pg/SQL output ok - $desc";
};

__DATA__

=== TEST 1: basic
--- in
    select foo, bar from Bah
--- ast
Query [Select [Column (Symbol "foo"),Column (Symbol "bar")],From [Model (Symbol "Bah")]]
--- out
select "foo", "bar" from "Bah"



=== TEST 2: select only
--- in

  select foo ; ;;
--- ast
Query [Select [Column (Symbol "foo")]]
--- out
select "foo"



=== TEST 3: spaces around separator (,)
--- in
select id,name , age from  Post , Comment;
--- ast
Query [Select [Column (Symbol "id"),Column (Symbol "name"),Column (Symbol "age")],From [Model (Symbol "Post"),Model (Symbol "Comment")]]
--- out
select "id", "name", "age" from "Post", "Comment"



=== TEST 4: spaces around separator (,)
--- in
select $foo,
$bar ,
$age from  Post , $comment
--- ast
Query [Select [Variable (1,9) "foo",Variable (2,2) "bar",Variable (3,2) "age"],From [Model (Symbol "Post"),Model (Variable (3,20) "comment")]]
--- out
select $foo, $bar, $age from "Post", $comment



=== TEST 5: simple where clause
--- in
select id from Post where a > b
--- ast
Query [Select [Column (Symbol "id")],From [Model (Symbol "Post")],Where (Compare ">" (Column (Symbol "a")) (Column (Symbol "b")))]
--- out
select "id" from "Post" where "a" > "b"



=== TEST 6: floating-point numbers
--- in
select id from Post where 00.003 > 3.14 or 3. > .0
--- out
select "id" from "Post" where (0.003 > 3.14 or 3.0 > 0.0)



=== TEST 7: integral numbers
--- in
select id from Post where 256 > 0
--- ast
Query [Select [Column (Symbol "id")],From [Model (Symbol "Post")],Where (Compare ">" (Integer 256) (Integer 0))]
--- out
select "id" from "Post" where 256 > 0



=== TEST 8: simple or
--- in
select id from Post  where a > b or b <= c
--- out
select "id" from "Post" where ("a" > "b" or "b" <= "c")



=== TEST 9: and in or
--- in
select id from Post where a>b and a like b or b=c and d>=e or e<>d
--- out
select "id" from "Post" where ((("a" > "b" and "a" like "b") or ("b" = "c" and "d" >= "e")) or "e" <> "d")



=== TEST 10: with parens in and/or
--- in
select id from Post where (( a > b ) and ( b < c or c > 1 ))
--- out
select "id" from "Post" where ("a" > "b" and ("b" < "c" or "c" > 1))



=== TEST 11: literal strings
--- in
select id from Post where 'a''\'' != 'b\\\n\r\b\a'
--- out
select "id" from "Post" where 'a''''' != 'b\\\n\r\ba'



=== TEST 12: order by
--- in
select id order  by  id
--- ast
Query [Select [Column (Symbol "id")],OrderBy [OrderPair (Column (Symbol "id")) (Keyword "asc")]]
--- out
select "id" order by "id" asc



=== TEST 13: complicated order by
--- in
select * order by id desc, name , foo  asc
--- out
select * order by "id" desc, "name" asc, "foo" asc



=== TEST 14: group by
--- in
select sum(id) group by id
--- out
select "sum"("id") group by "id"



=== TEST 15: select literals
--- in
 select 3.14 , 25, sum ( 1 ) , * from Post
--- out
select 3.14, 25, "sum"(1), * from "Post"



=== TEST 16: quoted symbols
--- in
select "id", "date_part"("created") from "Post" where "id" = 1
--- out
select "id", "date_part"("created") from "Post" where "id" = 1



=== TEST 17: offset and limit
--- in
select id from Post offset 3 limit 5
--- out
select "id" from "Post" offset 3 limit 5



=== TEST 18: offset and limit (with quoted values)
--- in
select id from Post offset '3' limit '5'
--- out
select "id" from "Post" offset '3' limit '5'



=== TEST 19: simple variable
--- in
select $var
--- ast
Query [Select [Variable (1,9) "var"]]
--- out
select $var



=== TEST 20: simple variable
--- in
select
$var
from Post
--- ast
Query [Select [Variable (2,2) "var"],From [Model (Symbol "Post")]]
--- out
select $var from "Post"



=== TEST 21: var in qualified col
--- in
select $table.$col from $table
--- ast
Query [Select [QualifiedColumn (Variable (1,9) "table") (Variable (1,16) "col")],From [Model (Variable (1,26) "table")]]
--- out
select $table.$col from $table



=== TEST 22: var in qualified col
--- in
select $table.col from $table
--- ast
Query [Select [QualifiedColumn (Variable (1,9) "table") (Symbol "col")],From [Model (Variable (1,25) "table")]]
--- out
select $table."col" from $table



=== TEST 23: var in proc call
--- in
select $proc(32)
--- ast
Query [Select [FuncCall (Variable (1,9) "proc") [Integer 32]]]
--- out
select $proc(32)



=== TEST 24: variable as model
--- in
select * from $model_name, $bar
--- ast
Query [Select [AnyColumn],From [Model (Variable (1,16) "model_name"),Model (Variable (1,29) "bar")]]
--- out
select * from $model_name, $bar



=== TEST 25: variable in where, offset, limit and group by
--- in
select * from A where $id > 0 offset $off limit $lim group by $foo
--- ast
Query [Select [AnyColumn],From [Model (Symbol "A")],Where (Compare ">" (Variable (1,24) "id") (Integer 0)),Offset (Variable (1,39) "off"),Limit (Variable (1,50) "lim"),GroupBy (Column (Variable (1,64) "foo"))]
--- out
select * from "A" where $id > 0 offset $off limit $lim group by $foo



=== TEST 26: weird identifiers
--- in
select select, 0.125 from from where where > or or and < and and order > 3.12 order by order, group group by by
--- out
select "select", 0.125 from "from" where ("where" > "or" or ("and" < "and" and "order" > 3.12)) order by "order" asc, "group" asc group by "by"



=== TEST 27: signed negative numbers
--- in
select -3 , - 3 , -1.25,- .3
--- ast
Query [Select [Minus (Integer 3),Minus (Integer 3),Minus (Float 1.25),Minus (Float 0.3)]]
--- out
select (-3), (-3), (-1.25), (-0.3)



=== TEST 28: signed positive numbers
--- in
select +3 , + 3 , +1.25,+ .3 , 1
--- ast
Query [Select [Plus (Integer 3),Plus (Integer 3),Plus (Float 1.25),Plus (Float 0.3),Integer 1]]
--- out
select 3, 3, 1.25, 0.3, 1



=== TEST 29: qualified columns
--- in
select Foo.bar , Foo . bar , "Foo" . bar , "Foo"."bar" from Foo
--- out
select "Foo"."bar", "Foo"."bar", "Foo"."bar", "Foo"."bar" from "Foo"



=== TEST 30: selected cols with parens
--- in
select (32) , ((5)) as item
--- ast
Query [Select [Integer 32,Alias (Integer 5) (Symbol "item")]]
--- out
select 32, 5 as "item"



=== TEST 31: count(*)
--- in
select count(*),
     count ( * )
 from Post
--- out
select "count"(*), "count"(*) from "Post"



=== TEST 32: aliased cols
--- in
select id as foo, count(*) as bar
from Post
--- ast
Query [Select [Alias (Column (Symbol "id")) (Symbol "foo"),Alias (FuncCall (Symbol "count") [AnyColumn]) (Symbol "bar")],From [Model (Symbol "Post")]]
--- out
select "id" as "foo", "count"(*) as "bar" from "Post"



=== TEST 33: alias for models
--- in
select * from Post as foo
--- ast
Query [Select [AnyColumn],From [Alias (Model (Symbol "Post")) (Symbol "foo")]]
--- out
select * from "Post" as "foo"



=== TEST 34: from proc
--- in
select *
from proc(32, 'hello'), blah() as poo
--- out
select * from "proc"(32, 'hello'), "blah"() as "poo"



=== TEST 35: arith
--- in
select 3+5/3*2 - 36 % 2
--- ast
Query [Select [Arith "-" (Arith "+" (Integer 3) (Arith "*" (Arith "/" (Integer 5) (Integer 3)) (Integer 2))) (Arith "%" (Integer 36) (Integer 2))]]
--- out
select ((3 + ((5 / 3) * 2)) - (36 % 2))



=== TEST 36: arith (with parens)
--- in
select (3+5)/(3*2) - ( 36 % 2 )
--- out
select (((3 + 5) / (3 * 2)) - (36 % 2))



=== TEST 37: string cat ||
--- in
select proc(2) || 'hello' || 5 - 2 + 5
--- out
select (("proc"(2) || 'hello') || ((5 - 2) + 5))



=== TEST 38: ^
--- in
select 3*3*5^6^2
--- out
select ((3 * 3) * ((5 ^ 6) ^ 2))



=== TEST 39: union
--- in
select 2 union select 3
--- ast
SetOp "union" (Query [Select [Integer 2]]) (Query [Select [Integer 3]])
--- out
((select 2) union (select 3))



=== TEST 40: union 2
--- in
(select count(*) from "Post" limit 3) union select sum(1) from "Comment";
--- out
((select "count"(*) from "Post" limit 3) union (select "sum"(1) from "Comment"))



=== TEST 41: chained union
--- in
select 3 union select 2 union select 1;
--- out
((((select 3) union (select 2))) union (select 1))



=== TEST 42: chained union and except
--- in
select 3 union select 2 union select 1 except select 2;
--- out
((((((select 3) union (select 2))) union (select 1))) except (select 2))



=== TEST 43: parens with set ops
--- in
select 3 union (select 2 except select 3)
--- out
((select 3) union (((select 2) except (select 3))))



=== TEST 44: intersect
--- in
(select 2) union (select 3)intersect(select 2)
--- out
((((select 2) union (select 3))) intersect (select 2))



=== TEST 45: intersect
--- in
(select 2) union ((select 3)intersect(select 2))
--- out
((select 2) union (((select 3) intersect (select 2))))



=== TEST 46: union all
--- in
select 2 union all select 2
--- ast
SetOp "union all" (Query [Select [Integer 2]]) (Query [Select [Integer 2]])
--- out
((select 2) union all (select 2))



=== TEST 47: type casting ::
--- in
select 32::float8
--- out
select 32::"float8"



=== TEST 48: more complicated type casting ::
--- in
select ('2003-03' || '-01') :: date
--- out
select ('2003-03' || '-01')::"date"



=== TEST 49: UTF-8
--- in
select '你好么？哈哈哈'
from Post
where 'hello' > 'グループ'
--- out
select '你好么？哈哈哈' from "Post" where 'hello' > 'グループ'



=== TEST 50: precedence of -
--- in
select -3::"text";
--- ast
Query [Select [Minus (TypeCast (Integer 3) (Column (Symbol "text")))]]
--- out
select (-3::"text")



=== TEST 51: precedence of -
--- in
select (-3)::"text";
--- ast
Query [Select [TypeCast (Minus (Integer 3)) (Column (Symbol "text"))]]
--- out
select (-3)::"text"



=== TEST 52: distinct
--- in
select distinct * from "Boh";
--- ast
Query [Select [Distinct [AnyColumn]],From [Model (Symbol "Boh")]]
--- out
select distinct * from "Boh"



=== TEST 53: union all
--- in
select 2 union all select 2;
--- out
((select 2) union all (select 2))



=== TEST 54: intersect all
--- in
select 2 intersect all select -2.0;
--- out
((select 2) intersect all (select (-2.0)))



=== TEST 55: except all
--- in
select * from "chen" except all select * from chen_bak
--- out
((select * from "chen") except all (select * from "chen_bak"))



=== TEST 56: distinct in count
--- in
select count(distinct rev) + 1 - 5 from logs
--- out
select (("count"(distinct "rev") + 1) - 5) from "logs"



=== TEST 57: distinct in column
--- in
select distinct rev from logs
--- out
select distinct "rev" from "logs"



=== TEST 58: $q$...$q$
--- in
select $q$'abc\'$q$ from Hello
--- out
select '''abc\\''' from "Hello"



=== TEST 59: $_$...$_$
--- in
select $_$hello," world$_$ from Hello
--- out
select 'hello," world' from "Hello"



=== TEST 60: $_123a_$...$_123a_$
--- in
select $_123a_$hello,"'\ world$_123a_$ from Hello
--- out
select 'hello,"''\\ world' from "Hello"



=== TEST 61: $q$$q$
--- in
select $q$$q$;
--- out
select ''



=== TEST 62: $$..$$
--- in
select $$$$, $$abc$$;
--- out
select '', 'abc'



=== TEST 63: true and false and null
--- in
select true, false, null
--- out
select true, false, null



=== TEST 64: where bool
--- in
select *
from Post
where true
--- out
select * from "Post" where true



=== TEST 65: where bool and bool
--- in
select *
from Post
where true and false
--- out
select * from "Post" where (true and false)



=== TEST 66: @@
--- in
select * from table where field @@ to_tsquery('chinesecfg', $keyword)
--- out
select * from "table" where "field" @@ "to_tsquery"('chinesecfg', $keyword)



=== TEST 67: >>=
--- in
select * from table where field >>= '127.0.0.1'
--- out
select * from "table" where "field" >>= '127.0.0.1'



=== TEST 68: Test potential ambiguity between variables and verbatim quotes (the wrong way)
--- in
select $foo , $foo$hello$foo from Post
--- error
"view" (line 1, column 19):
unexpected "$"



=== TEST 69: Test potential ambiguity between variables and verbatim quotes (the right way)
--- in
select $foo , $foo$hello$foo$ from Post
--- out
select $foo, 'hello' from "Post"



=== TEST 70: Test @>
--- in
select * from A where a @> 'hello'
--- out
select * from "A" where "a" @> 'hello'



=== TEST 71: Test @<
--- in
select * from A where a @< 'hello'
--- out
select * from "A" where "a" @< 'hello'



=== TEST 72: as (col1 type1, col2 type2, ...)
--- in
select * from getquery($spell) as (query text, pop integer, des text) limit $t;
--- ast
Query [Select [AnyColumn],From [Alias (FuncCall (Symbol "getquery") [Variable (1,25) "spell"]) (Capture [(Symbol "query",Type "text"),(Symbol "pop",Type "integer"),(Symbol "des",Type "text")])],Limit (Variable (1,78) "t")]
--- out
select * from "getquery"($spell) as ("query" text, "pop" integer, "des" text) limit $t



=== TEST 73: builtin vars
--- in
select $_ACCOUNT as account, $_ROLE as role
--- ast
Query [Select [Alias (Variable (1,9) "_ACCOUNT") (Symbol "account"),Alias (Variable (1,31) "_ROLE") (Symbol "role")]]
--- out
select $_ACCOUNT as "account", $_ROLE as "role"



=== TEST 74: is null
--- in
select * from Foo where col is null
--- out
select * from "Foo" where "col" is null



=== TEST 75: is not null
--- in
select * from Foo where col is not null
--- out
select * from "Foo" where "col" is not null


=== TEST 76: array indexing
--- in
select m.mid, m.title,
    (regexp_split_to_array(m.blob_client_data1, ' '))[58] as subject,
    (regexp_split_to_array(m.blob_client_data1, ' '))[69] as article
from mob as m,
    (select * from yid_lookup as y where y.yuid like '%' || $yuid || '%') as t
where m.yid = t.id;
--- out
select "m"."mid", "m"."title", ("regexp_split_to_array"("m"."blob_client_data1", ' '))[58] as "subject", ("regexp_split_to_array"("m"."blob_client_data1", ' '))[69] as "article" from "mob" as "m", select * from "yid_lookup" as "y" where "y"."yuid" like (('%' || $yuid) || '%') as "t" where "m"."yid" = "t"."id"

