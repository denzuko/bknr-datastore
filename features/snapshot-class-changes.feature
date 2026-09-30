Feature: Reloading a snapshot after a class gains a slot
  As a program whose persistent classes change between releases
  I want slots added since a snapshot to take their initform on reload
  So that migrating an older store needs no code for new slots

  Expected behaviour, from the sources:
    - Archived upstream issue #24 (2022): after a class changes, bknr leaves
      new slots unbound instead of binding their :initform.
    - bknr datastore manual, store internals: when a class definition is
      changed, the existing instances are updated accordingly.
    - CLHS 4.3.6, Redefining Classes: local slots added to a class are
      initialised from their initforms by UPDATE-INSTANCE-FOR-REDEFINED-CLASS.
    - object.lisp, the snapshot writer: it records every persistent slot
      of the class, writing UNBOUND for an unbound slot.

  Background:
    Given an empty store for migrating things

  Scenario: A slot added after the snapshot takes its initform on reload
    Given 3 migrating things with name "a", snapshotted under the first class
    When the class gains a slot "level" with initform 42
    And the store is reopened
    Then every migrating thing should have level 42
    And every migrating thing should keep its name "a"

  Scenario: A mismatch between snapshot and class keeps the recorded values
    Given 1 migrating thing with name "kept", snapshotted under the first class
    When the class gains a slot "level" with initform 42
    And the store is reopened
    Then every migrating thing should keep its name "kept"

  Scenario: A slot recorded as empty in the snapshot stays empty
    Given 1 migrating thing with no name, snapshotted under the first class
    When the class gains a slot "level" with initform 42
    And the store is reopened
    Then every migrating thing should have no name
    And every migrating thing should have level 42

  Scenario: A slot added without an initform stays unbound
    Given 1 migrating thing with name "a", snapshotted under the first class
    When the class gains a slot "level" with no initform
    And the store is reopened
    Then every migrating thing should have no level

  Scenario: A large store gets the initform on every object
    Given 500 migrating things with name "a", snapshotted under the first class
    When the class gains a slot "level" with initform 42
    And the store is reopened
    Then every migrating thing should have level 42

  Scenario: The initialised value survives another snapshot and reload
    Given 2 migrating things with name "a", snapshotted under the first class
    When the class gains a slot "level" with initform 42
    And the store is reopened
    And the store is snapshotted and reopened again
    Then every migrating thing should have level 42
