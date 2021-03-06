use Test::Base;
use JSON::XS;

plan tests => 2* blocks() + 106;

require OpenResty::QuasiQuote::Validator::Compiler;

my $json_xs = JSON::XS->new->utf8->allow_nonref;

my $val = OpenResty::QuasiQuote::Validator::Compiler->new;

#no_diff;

sub validate { 1; }

run {
    my $block = shift;
    my $name = $block->name;
    my $perl;
    if (!$block->spec) { die "$name - No spec specified.\n" }
    eval {
        $perl = $val->validator($block->spec);
    };
    if ($@) {
        die "$name - $@";
    }
    my $expected = $block->perl;
    $expected =~ s/^\s+//gm;
    is $perl, $expected, "$name - perl code match";
    my $code = "*validate = sub { local \$_ = shift; $perl }";
    {
        no warnings 'redefine';
        no strict;
        eval $code;
        if ($@) {
            fail "$name - Bad perl code emitted - $@";
            *validate = sub { 1 };
        } else {
            pass "$name - perl code emitted is well formed";
        }
    }
    my $spec = $block->valid;
    if ($spec) {
        my @ln = split /\n/, $spec;
        for my $ln (@ln) {
            my $data = $json_xs->decode($ln);
            eval {
                validate($data);
            };
            if ($@) {
                fail "$name - Valid data <<$ln>> is valid - $@";
            } else {
                pass "$name - Valid data <<$ln>> is valid";
            }
        }
    }
    $spec = $block->invalid;
    if ($spec) {
        my @ln = split /\n/, $spec;
        while (@ln) {
            my $ln = shift @ln;
            my $excep = shift @ln;
            my $data = $json_xs->decode($ln);
            eval {
                validate($data);
            };
            unless ($@) {
                fail "$name - Invalid data <<$ln>> is invalid - $@";
            } else {
                is $@, "$excep\n", "$name - Invalid data <<$ln>> is invalid";
            }
        }
    }

};

__DATA__

=== TEST 1: simple hash
---  spec
{ foo: STRING }
--- perl
if (defined) {
    ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
    {
        local *_ = \( $_->{"foo"} );
        if (defined) {
            !ref or die qq{Bad value for "foo": String expected.\n};
        }
    }
    for (keys %$_) {
        $_ eq "foo" or die qq{Unrecognized key in hash: $_\n};
    }
}
--- valid
{"foo":"dog"}
{"foo":32}
null
{}
--- invalid
{"foo2":32}
Unrecognized key in hash: foo2
32
Invalid value: Hash expected.
[]
Invalid value: Hash expected.



=== TEST 2: strings
---  spec
STRING
--- perl
if (defined) {
    !ref or die qq{Bad value: String expected.\n};
}
--- valid
"hello"
32
3.14
null
0
--- invalid
{"cat":32}
Bad value: String expected.
[1,2,3]
Bad value: String expected.



=== TEST 3: numbers
---  spec
INT
--- perl
if (defined) {
    /^[-+]?\d+$/ or die qq{Bad value: Integer expected.\n};
}
--- valid
32
0
null
-56
--- invalid
3.14
Bad value: Integer expected.
"hello"
Bad value: Integer expected.
[0]
Bad value: Integer expected.
{}
Bad value: Integer expected.



=== TEST 4: identifiers
---  spec
IDENT
--- perl
if (defined) {
    /^[A-Za-z]\w*$/ or die qq{Bad value: Identifier expected.\n};
}
--- valid
"foo"
"hello_world"
"HiBoy"
--- invalid
"_foo"
Bad value: Identifier expected.
"0a"
Bad value: Identifier expected.
32
Bad value: Identifier expected.
[]
Bad value: Identifier expected.
{"cat":3}
Bad value: Identifier expected.



=== TEST 5: arrays
--- spec
[STRING]
--- perl
if (defined) {
    ref and ref eq 'ARRAY' or die qq{Invalid value: Array expected.\n};
    for (@$_) {
        if (defined) {
            !ref or die qq{Bad value for array element: String expected.\n};
        }
    }
}
--- valid
[1,2]
["hello"]
null
[]

--- invalid
[[1]]
Bad value for array element: String expected.
32
Invalid value: Array expected.
"hello"
Invalid value: Array expected.
{}
Invalid value: Array expected.



=== TEST 6: hashes of arrays
--- spec
{ columns: [ { name: STRING, type: STRING } ] }
--- perl
if (defined) {
    ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
    {
        local *_ = \( $_->{"columns"} );
        if (defined) {
            ref and ref eq 'ARRAY' or die qq{Invalid value for "columns": Array expected.\n};
            for (@$_) {
                if (defined) {
                    ref and ref eq 'HASH' or die qq{Invalid value for "columns" array element: Hash expected.\n};
                    {
                        local *_ = \( $_->{"name"} );
                        if (defined) {
                            !ref or die qq{Bad value for "name" for "columns" array element: String expected.\n};
                        }
                    }
                    {
                        local *_ = \( $_->{"type"} );
                        if (defined) {
                            !ref or die qq{Bad value for "type" for "columns" array element: String expected.\n};
                        }
                    }
                    for (keys %$_) {
                        $_ eq "name" or $_ eq "type" or die qq{Unrecognized key in hash for "columns" array element: $_\n};
                    }
                }
            }
        }
    }
    for (keys %$_) {
        $_ eq "columns" or die qq{Unrecognized key in hash: $_\n};
    }
}
--- valid
{"columns":[]}
{"columns":[{"name":"Carrie"}]}
{"columns":null}
{"columns":[{"name":null,"type":null}]}
{}
null
--- invalid
{"bar":[]}
Unrecognized key in hash: bar
{"columns":[{"default":32,"blah":[]}]}
Unrecognized key in hash for "columns" array element: blah
{"columns":[32]}
Invalid value for "columns" array element: Hash expected.
32
Invalid value: Hash expected.



=== TEST 7: simple hash required
---  spec
{ "foo": STRING } :required
--- perl
defined or die qq{Value required.\n};
ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
{
    local *_ = \( $_->{"foo"} );
    if (defined) {
        !ref or die qq{Bad value for "foo": String expected.\n};
    }
}
for (keys %$_) {
    $_ eq "foo" or die qq{Unrecognized key in hash: $_\n};
}
--- valid
{"foo":"hello"}
{}
{"foo":null}

--- invalid
null
Value required.
{"blah":"hi"}
Unrecognized key in hash: blah
[]
Invalid value: Hash expected.
32
Invalid value: Hash expected.



=== TEST 8: array required
--- spec
[INT] :required(1)
--- perl
defined or die qq{Value required.\n};
ref and ref eq 'ARRAY' or die qq{Invalid value: Array expected.\n};
for (@$_) {
    if (defined) {
        /^[-+]?\d+$/ or die qq{Bad value for array element: Integer expected.\n};
    }
}
--- valid
[1,2]
[0]
--- invalid
["hello"]
Bad value for array element: Integer expected.
[1,2,"hello"]
Bad value for array element: Integer expected.
[1.32]
Bad value for array element: Integer expected.
null
Value required.



=== TEST 9: array elem required
--- spec
[INT :required]
--- perl
if (defined) {
    ref and ref eq 'ARRAY' or die qq{Invalid value: Array expected.\n};
    for (@$_) {
        defined or die qq{Value for array element required.\n};
        /^[-+]?\d+$/ or die qq{Bad value for array element: Integer expected.\n};
    }
}

--- valid
[32]
null
[]
--- invalid
[null]
Value for array element required.



=== TEST 10: nonempty array
--- spec
[INT] :nonempty
--- perl
if (defined) {
    ref and ref eq 'ARRAY' or die qq{Invalid value: Array expected.\n};
    @$_ or die qq{Array cannot be empty.\n};
    for (@$_) {
        if (defined) {
            /^[-+]?\d+$/ or die qq{Bad value for array element: Integer expected.\n};
        }
    }
}
--- valid
[32]
[1,2]
null
--- invalid
[]
Array cannot be empty.



=== TEST 11: nonempty required array
--- spec
[INT] :nonempty :required
--- perl
defined or die qq{Value required.\n};
ref and ref eq 'ARRAY' or die qq{Invalid value: Array expected.\n};
@$_ or die qq{Array cannot be empty.\n};
for (@$_) {
    if (defined) {
        /^[-+]?\d+$/ or die qq{Bad value for array element: Integer expected.\n};
    }
}
--- valid
[32]
[1,2]
--- invalid
[]
Array cannot be empty.
null
Value required.
["hello"]
Bad value for array element: Integer expected.



=== TEST 12: nonempty hash
--- spec
{"cat":STRING}:nonempty
--- perl
if (defined) {
    ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
    %$_ or die qq{Hash cannot be empty.\n};
    {
        local *_ = \( $_->{"cat"} );
        if (defined) {
            !ref or die qq{Bad value for "cat": String expected.\n};
        }
    }
    for (keys %$_) {
        $_ eq "cat" or die qq{Unrecognized key in hash: $_\n};
    }
}
--- valid
{"cat":32}
null
--- invalid
32
Invalid value: Hash expected.
{}
Hash cannot be empty.



=== TEST 13: scalar required
--- spec
IDENT :required
--- perl
defined or die qq{Value required.\n};
/^[A-Za-z]\w*$/ or die qq{Bad value: Identifier expected.\n};



=== TEST 14: scalar required
--- spec
STRING :required
--- perl
defined or die qq{Value required.\n};
!ref or die qq{Bad value: String expected.\n};



=== TEST 15: scalar required in a hash
--- spec
{ name: STRING :required, type: STRING :required }
--- perl
if (defined) {
    ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
    {
        local *_ = \( $_->{"name"} );
        defined or die qq{Value for "name" required.\n};
        !ref or die qq{Bad value for "name": String expected.\n};
    }
    {
        local *_ = \( $_->{"type"} );
        defined or die qq{Value for "type" required.\n};
        !ref or die qq{Bad value for "type": String expected.\n};
    }
    for (keys %$_) {
        $_ eq "name" or $_ eq "type" or die qq{Unrecognized key in hash: $_\n};
    }
}
--- invalid
{"name":"hi","type":"text","default":"Howdy"}
Unrecognized key in hash: default



=== TEST 16: scalar required in a hash which is required also
--- spec
{ name: STRING :required, type: STRING :required } :required
--- perl
defined or die qq{Value required.\n};
ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
{
    local *_ = \( $_->{"name"} );
    defined or die qq{Value for "name" required.\n};
    !ref or die qq{Bad value for "name": String expected.\n};
}
{
    local *_ = \( $_->{"type"} );
    defined or die qq{Value for "type" required.\n};
    !ref or die qq{Bad value for "type": String expected.\n};
}
for (keys %$_) {
    $_ eq "name" or $_ eq "type" or die qq{Unrecognized key in hash: $_\n};
}



=== TEST 17: default string
--- spec
STRING :default('hello')
--- perl
if (defined) {
    !ref or die qq{Bad value: String expected.\n};
}
else {
    $_ = 'hello';
}



=== TEST 18: default array
--- spec
[STRING :default(32)] : default([])
--- perl
if (defined) {
    ref and ref eq 'ARRAY' or die qq{Invalid value: Array expected.\n};
    for (@$_) {
        if (defined) {
            !ref or die qq{Bad value for array element: String expected.\n};
        }
        else {
            $_ = 32;
        }
    }
}
else {
    $_ = [];
}
--- valid
[]
null



=== TEST 19: assign for array and scalar
--- spec
[STRING :default(32) :to($bar) ] :to($foo) :default([])
--- perl
if (defined) {
    ref and ref eq 'ARRAY' or die qq{Invalid value: Array expected.\n};
    for (@$_) {
        if (defined) {
            !ref or die qq{Bad value for array element: String expected.\n};
        }
        else {
            $_ = 32;
        }
        $bar = $_;
    }
}
else {
    $_ = [];
}
$foo = $_;



=== TEST 20: assign for hash
--- spec
{"name": STRING :to($name) :required, "type": STRING :to($type) :default("text")} :to($column)
--- perl
if (defined) {
    ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
    {
        local *_ = \( $_->{"name"} );
        defined or die qq{Value for "name" required.\n};
        !ref or die qq{Bad value for "name": String expected.\n};
        $name = $_;
    }
    {
        local *_ = \( $_->{"type"} );
        if (defined) {
            !ref or die qq{Bad value for "type": String expected.\n};
        }
        else {
            $_ = "text";
        }
        $type = $_;
    }
    for (keys %$_) {
        $_ eq "name" or $_ eq "type" or die qq{Unrecognized key in hash: $_\n};
    }
}
$column = $_;
--- valid
{"name":"Hello","type":"text"}



=== TEST 21: $foo ~~
--- spec
$data ~~ { "name": STRING }
--- perl
{
    local *_ = \( $data );
    if (defined) {
        ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
        {
            local *_ = \( $_->{"name"} );
            if (defined) {
            !ref or die qq{Bad value for "name": String expected.\n};
            }
        }
        for (keys %$_) {
            $_ eq "name" or die qq{Unrecognized key in hash: $_\n};
        }
    }
}



=== TEST 22: $foo->{bar} ~~
--- spec
$foo->{bar} ~~ { "name": STRING }
--- perl
{
    local *_ = \( $foo->{bar} );
    if (defined) {
        ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
        {
            local *_ = \( $_->{"name"} );
            if (defined) {
            !ref or die qq{Bad value for "name": String expected.\n};
            }
        }
        for (keys %$_) {
            $_ eq "name" or die qq{Unrecognized key in hash: $_\n};
        }
    }
}



=== TEST 23: match(/.../, '...')
--- spec
STRING :match(/^\d{4}-\d{2}-\d{2}$/, 'Date')
--- perl
if (defined) {
    !ref or die qq{Bad value: String expected.\n};
    /^\d{4}-\d{2}-\d{2}$/ or die qq{Invalid value: Date expected.\n};
}



=== TEST 24: :allowed
--- spec
STRING :allowed('password', 'login', 'anonymous')
--- perl
if (defined) {
    !ref or die qq{Bad value: String expected.\n};
    $_ eq 'password' or $_ eq 'login' or $_ eq 'anonymous' or die qq{Invalid value: Allowed values are 'password', 'login', 'anonymous'.\n};
}
--- valid
"password"
"login"
"anonymous"
null
--- invalid
""
Invalid value: Allowed values are 'password', 'login', 'anonymous'.



=== TEST 25: :allowed and :match in hashes
--- spec
{
    cat: STRING :match(/mimi|papa/, 'Cat name') :required,
    dog: STRING :allowed('John', 'Mike'),
}
--- perl
if (defined) {
    ref and ref eq 'HASH' or die qq{Invalid value: Hash expected.\n};
    {
        local *_ = \( $_->{"cat"} );
        defined or die qq{Value for "cat" required.\n};
        !ref or die qq{Bad value for "cat": String expected.\n};
        /mimi|papa/ or die qq{Invalid value for "cat": Cat name expected.\n};
    }
    {
        local *_ = \( $_->{"dog"} );
        if (defined) {
            !ref or die qq{Bad value for "dog": String expected.\n};
            $_ eq 'John' or $_ eq 'Mike' or die qq{Invalid value for "dog": Allowed values are 'John', 'Mike'.\n};
        }
    }
    for (keys %$_) {
        $_ eq "cat" or $_ eq "dog" or die qq{Unrecognized key in hash: $_\n};
    }
}
--- valid
null
{"cat":"mimi"}
{"cat":"mimi","dog":"John"}
{"cat":"papa","dog":"Mike"}
--- invalid
{"cat":"mini"}
Invalid value for "cat": Cat name expected.
{"cat":"papa","dog":"John Zhang"}
Invalid value for "dog": Allowed values are 'John', 'Mike'.



=== TEST 26: nonempty values
--- spec
STRING :nonempty
--- perl
if (defined) {
    !ref or die qq{Bad value: String expected.\n};
    length or die qq{Invalid value: Nonempty scalar expected.\n};
}

--- valid
null
"hello"
0
1
--- invalid
""
Invalid value: Nonempty scalar expected.
true
Bad value: String expected.
false
Bad value: String expected.



=== TEST 27: BOOL
--- spec
BOOL
--- perl
if (defined) {
    JSON::XS::is_bool($_) or die qq{Bad value: Boolean expected.\n};
}
--- valid
true
false
null
--- invalid
"hello"
Bad value: Boolean expected.
0
Bad value: Boolean expected.
1
Bad value: Boolean expected.

