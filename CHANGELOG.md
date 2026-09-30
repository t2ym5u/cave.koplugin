# Changelog

All notable changes to this project will be documented in this file.

## [1.2.0] - 2026-09-30

### Added
- **Hint** button. Two taps, not one: the first says which cell is about to
  give, the second acts on it -- a player who is told where to look usually
  finds the rest themselves, and only pays for the full reveal if they want
  it. A cell that contradicts the solution is always reported before a fresh
  one is revealed, and on a mistake the hint empties the cell rather than
  solving it.

## [1.1.7] - 2026-07-28

### Fixed
- Generated puzzles had no uniqueness verification at all — measured as
  low as 0 in 10 puzzles actually having a unique solution at some
  size/difficulty combinations. Added a uniqueness solver and reworked
  generation to verify each puzzle before accepting it. 6×6 puzzles are
  now guaranteed unique at every difficulty; medium difficulty at 7×7 and
  8×8 is a documented partial improvement (see README).
