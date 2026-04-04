# BNF Grammar for Rounds

```bnf
<rounds_file>    ::= <newlines> <defaults_section>? <round_section>* EOF

<defaults_section> ::= "[" DEFAULTS "]" <newlines> <setting>*

<setting>        ::= IDENT "=" INT <newlines>

<round_section>  ::= "[" ROUND IDENT "]" <newlines> <entry>*

<entry>          ::= BREAK <newlines>
                   | BREAK INT <newlines>
                   | PATH <song_option>* <newlines>

<song_option>    ::= "|" IDENT "=" INT

<newlines>       ::= NEWLINE*
```
