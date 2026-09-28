Feature: Temporary pathnames
  As a program that needs a scratch file
  I want MAKE-TEMPORARY-PATHNAME and WITH-TEMPORARY-FILE to work on a
  conforming Common Lisp
  So that tests and callers get a usable pathname with no arguments

  Expected behaviour, from the sources:
    - CLHS MAKE-PATHNAME: DEFAULTS is a pathname designator; when it is not
      supplied, the default is a pathname with the host of
      *DEFAULT-PATHNAME-DEFAULTS* and every other component NIL.
    - CLHS glossary: a pathname designator is a namestring, a stream
      associated with a file, or a pathname. NIL is none of these.
    - utils.lisp, MAKE-TEMPORARY-PATHNAME: the name is NAME, the universal
      time and a random number joined by hyphens, and the loop returns only
      a pathname that names no existing file.
    - utils.lisp, WITH-TEMPORARY-FILE: after BODY, the file is deleted if it
      exists, through UNWIND-PROTECT.
    - object-tests.lisp, MAKE-TEST-STORE-DIRECTORY: names are not guaranteed
      to be distinct across calls, so no scenario asserts that.

  Scenario: Called with no arguments, the pathname carries only the default host
    When I make a temporary pathname with no arguments
    Then its name should start with "tmp-"
    And it should have no directory
    And its host should be the host of the default pathname defaults

  Scenario: Called with a directory as defaults, the pathname is in that directory
    When I make a temporary pathname with defaults "/tmp/"
    Then its directory should be "/tmp/"

  Scenario: Called with a name, the pathname name starts with it
    When I make a temporary pathname with the name "store-test"
    Then its name should start with "store-test-"

  Scenario: An empty name prefix still yields a pathname naming no existing file
    When I make a temporary pathname with the name ""
    Then its name should start with "-"
    And it should name no existing file

  Scenario: Defaults that are not a pathname designator are refused
    When I make a temporary pathname with the number 42 as defaults
    Then an error should have been signalled

  Scenario: Concurrent callers each get a pathname naming no existing file
    When 8 threads each make 20 temporary pathnames with defaults "/tmp/"
    Then every pathname should name no existing file

  Scenario: A file written inside WITH-TEMPORARY-FILE does not survive the block
    When I write a file inside WITH-TEMPORARY-FILE with defaults "/tmp/"
    Then the file should not exist after the block

  Scenario: A file written before an error does not survive the block
    When I write a file inside WITH-TEMPORARY-FILE with defaults "/tmp/" and then signal an error
    Then the file should not exist after the block
    And the error should have reached the caller

  Scenario: A block that writes nothing leaves nothing and signals nothing
    When I run WITH-TEMPORARY-FILE with defaults "/tmp/" without writing
    Then no error should have been signalled
    And the file should not exist after the block
