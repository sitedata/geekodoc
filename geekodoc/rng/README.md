# README


## What?
This directory contains RELAX NG files to validate the SUSE
documentation.


## Where?

There are two incarnations of the SUSE schema:

* `geekodoc5.rnc`
   This is the main file where development is taking place. This file
   depends on `docbookxi.rnc` (version 5.1). It doesn't work without
   this file.

* `geekodoc5-flat.rnc`
   This file is generated. It doesn't contain any dependency to DocBook
   5.1 anymore. If you need a file which is self-contained, use this.

The schema itself is delivered both as RNC (compact RELAX NG) and as RNG
(XML).

