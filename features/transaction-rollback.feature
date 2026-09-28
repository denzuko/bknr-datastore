Feature: Rolling back an anonymous transaction
  As a program that uses WITH-TRANSACTION
  I want a transaction that signals an error to leave the store as it was
  So that indices, object ids and the transaction log stay consistent

  Expected behaviour, from the sources:
    - fc4e7be (rollback commit): every slot write in the failed transaction
      is undone, and objects it created leave their indices.
    - protocol.lisp, INDEX-REMOVE: remove OBJECT from the index.
    - tutorial.lisp, object store: every store object has a unique id.
    - object-tests.lisp, DO-RUN-TEST: a restore, and a snapshot followed by
      a restore, reproduce the live objects and the live id counter.

  Background:
    Given an empty store

  Scenario: A successful transaction keeps the object it created
    When a transaction creates a thing with key "kept"
    Then 1 thing should exist
    And the thing with key "kept" should be found by its key and by its id

  Scenario: A failed transaction leaves no object it created
    When a transaction creates a thing with key "gone" and then signals an error
    Then 0 things should exist
    And no thing should be found under the key "gone"

  Scenario: A failed transaction restores the slots it changed
    Given a thing with key "a" and note "before"
    When a transaction sets the note of "a" to "after" and then signals an error
    Then the note of "a" should be "before"

  Scenario: A transaction that fails on a duplicate key keeps the existing object
    Given a thing with key "taken" and note "original"
    When a transaction creates a thing with the duplicate key "taken"
    Then the transaction should have signalled an index error
    And the thing with key "taken" should have note "original"
    And 1 thing should exist

  Scenario: A failed transaction that created nothing leaves the id counter at zero
    When a transaction that creates nothing signals an error
    Then the id counter should be 0

  Scenario: The object created after a rollback reuses the rolled-back id
    When a transaction creates a thing with key "gone" and then signals an error
    And a thing with key "next" is created outside a transaction
    Then the thing with key "next" should have id 0
    And the thing with key "next" should be found by its key and by its id

  Scenario: Concurrent creations beside failing transactions get unique ids
    When 8 threads create things while 8 threads run failing transactions, 30 rounds each
    Then 240 things should exist
    And every thing should have a unique id
    And every thing should be found by its key and by its id

  Scenario: Failed transactions leave a store that survives a reload
    When 8 threads create things while 8 threads run failing transactions, 10 rounds each
    And the store is restored
    Then 80 things should exist
    And the restored ids and id counter should match the live store

  Scenario: Failed transactions leave a store that survives a snapshot and reload
    When 8 threads create things while 8 threads run failing transactions, 10 rounds each
    And the store is snapshotted and restored
    Then 80 things should exist
    And the restored ids and id counter should match the live store
