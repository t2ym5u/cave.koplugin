# Changelog

All notable changes to this project will be documented in this file.

## [1.1.7] - 2026-07-28

### Fixed
- Generated puzzles had no uniqueness verification at all — measured as
  low as 0 in 10 puzzles actually having a unique solution at some
  size/difficulty combinations. Added a uniqueness solver and reworked
  generation to verify each puzzle before accepting it. 6×6 puzzles are
  now guaranteed unique at every difficulty; medium difficulty at 7×7 and
  8×8 is a documented partial improvement (see README).
