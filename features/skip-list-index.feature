Feature: Removing objects from a skip-list index
  As a program that indexes a slot with SKIP-LIST-INDEX
  I want removal to take out only the object asked for
  So that a rollback or a delete never loses another object's entry

  Expected behaviour, from the sources:
    - protocol.lisp, INDEX-REMOVE: remove OBJECT from the index.
    - indices.lisp, INDEX-ADD for SKIP-LIST-INDEX: an object with an unbound
      key slot is not added, a NIL key is not added unless INDEX-NIL is set,
      and a key another object holds signals INDEX-EXISTING-ERROR.
    - fc4e7be (rollback commit): a failed anonymous transaction undoes its
      slot writes, and objects it created leave their indices.
    - indices.lisp, INDEX-REINITIALIZE for SKIP-LIST-INDEX: a redefined class
      keeps its entries; the new index takes over the old skip list.
    - txn.lisp: transactions run one at a time under the store guard, and a
      restore rebuilds every index from the snapshot and log.

  Background:
    Given an empty store with a class keyed by a skip-list index

  Scenario: Removing the object that holds its key takes it out
    Given a ranked thing with rank 3
    When the ranked thing with rank 3 is removed from the index
    Then no ranked thing should be found under rank 3

  Scenario: Removing the wrong object leaves the holder in place
    Given a ranked thing with rank 3
    When an unindexed ranked thing with rank 3 is removed from the index
    Then the first ranked thing should be found under rank 3

  Scenario: Removing an object whose key slot is empty leaves the index unchanged
    Given a ranked thing with rank 3
    When an unindexed ranked thing with no rank is removed from the index
    Then the removal should have signalled nothing
    And the first ranked thing should be found under rank 3

  Scenario: A duplicate-key rollback keeps the existing entry
    Given a ranked thing with rank 3
    When a transaction creates a ranked thing with the duplicate rank 3
    Then the duplicate rank should have been refused with an index error
    And the first ranked thing should be found under rank 3
    And 1 ranked thing should exist

  Scenario: Concurrent transactions each find their own entry
    When 8 threads each create 20 ranked things in transactions
    Then 160 ranked things should exist
    And every ranked thing should be found under its rank

  Scenario: The index survives a reload after a duplicate-key rollback
    Given a ranked thing with rank 3
    When a transaction creates a ranked thing with the duplicate rank 3
    And the store is reloaded
    Then the first ranked thing should be found under rank 3
    And 1 ranked thing should exist

  Scenario: Entries survive a redefinition of the indexed class
    Given a ranked thing with rank 3
    When the ranked thing class is defined again
    Then the first ranked thing should be found under rank 3
    And 1 ranked thing should exist
