# PG2L200H Document Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove obsolete PG2L200H documentation and make active project and learning material describe the PG2L200H 200Pro+ target.

**Architecture:** Treat `docs/board/pg2l200h_*.md` and the current board top as the only board-specific source of truth. Preserve algorithm explanations while replacing retired board integration, clock, memory, PDS, and naming details.

**Tech Stack:** Markdown, SystemVerilog project structure, Pango PDS 2022.2-SP6.4.

## Global Constraints

- Target board: `PG2L200H-6FBB676` (Logos2 / 盘古200Pro+).
- Board clocks: 27 MHz `sys_clk`, 125 MHz differential DDR reference, 74.25 MHz 720p60 output.
- Physical top: `pg2l200h_board_top`; board path: `boards/pg2l200h`.
- DDR3 and PLL assets come from `ip/pango/pg2l200h`.
- Do not retain PG2L200H, 盘古200Pro+, or retired-board paths in active documentation.

### Task 1: Retire old-board archive

**Files:**
- Delete: `docs/archive/pg2l200h/`

- [ ] Delete the verified PG2L200H-only archive directory.
- [ ] Confirm the directory no longer exists.

### Task 2: Update active project documentation

**Files:**
- Modify: `README.md`, `docs/plans/**`, `docs/superpowers/plans/**`, `docs/superpowers/specs/**`

- [ ] Rename old-board filenames to PG2L200H-neutral names.
- [ ] Replace retired device, path, clock, DDR, timing-mode, and cache-capacity claims with current values.
- [ ] Retain board-independent algorithm and workflow explanations.

### Task 3: Update learning material

**Files:**
- Modify: `learning/*.md`

- [ ] Update board names, top-level hierarchy, PDS paths, IP names, and constraints to the 200Pro+ implementation.
- [ ] Preserve algorithm, cache, FIFO, and timing explanations that remain board-independent.

### Task 4: Audit

**Files:**
- Verify: `README.md`, `docs/**`, `learning/**`

- [ ] Search all active documentation for PG2L200H, 盘古200Pro+, Pango 200Pro+, and retired paths.
- [ ] Inspect target-board facts against `docs/board/pg2l200h_*.md`.
