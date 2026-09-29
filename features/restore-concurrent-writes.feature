Feature: Writes from another thread while a restore runs
  As a program that restores a store while other threads are live
  I want those threads held to the same rules as outside a transaction
  So that nothing they do escapes the transaction log

  Expected behaviour, from the sources:
    - object.lisp, (SETF SLOT-VALUE-USING-CLASS) :BEFORE: a persistent slot
      written outside a transaction signals
      PERSISTENT-SLOT-MODIFIED-OUTSIDE-OF-TRANSACTION.
    - object.lisp, INITIALIZE-INSTANCE :AROUND: MAKE-INSTANCE outside a
      transaction runs as a logged transaction under the store guard.
    - txn.lisp, RESTORE-STORE: the restore holds the store guard, and its
      comment states that subsystems may not make persistent changes while
      restoring.
    - object-tests.lisp, DO-RUN-TEST: a restore reproduces the live objects
      and the live id counter.
  A thread that is not running the restore is outside any transaction, so
  these rules apply to it unchanged.

  Background:
    Given a store holding a record with key "k" and note "before", snapshotted
    And a restore paused after the snapshot is loaded, in its own thread

  Scenario: A slot write from another thread during a restore is refused
    When this thread sets the note of "k" to "during"
    And the restore is released
    Then the write should have signalled a modified-outside-of-transaction error
    And the note of record "k" should be "before"

  Scenario: A single record created from another thread waits for the restore
    When another thread creates a record with key "made-during"
    Then that creation should still be waiting after 200 milliseconds
    And the id counter should be unchanged while the restore is paused
    When the restore is released
    Then the creation should finish
    And the record with key "made-during" should be found by its key and by its id

  Scenario: Concurrent creations during a restore get unique ids
    When 4 other threads each create 5 records
    And the restore is released
    Then the creations should finish
    And 21 records should exist
    And every record should have a unique id

  Scenario: A record created during a restore survives a reload
    When another thread creates a record with key "made-during"
    And the restore is released
    Then the creation should finish
    When the store is restored again
    Then the record with key "made-during" should be found by its key and by its id
    And the restored record ids and id counter should match the live store
