# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`Ledger.pm` is a Perl library for personal accounting that reads, parses, and writes transactions in [Ledger-CLI](https://ledger-cli.org/) format. It imports financial data from OFX/QFX, CSV, and JSON (Plaid/Teller APIs), matches pending transactions against existing ones using heuristic scoring, and writes changes back to ledger files in-place.

## Dependencies

Perl modules required: `Storable`, `YAML::Tiny`, `Text::CSV`, `Date::Parse`, `JSON`, `POSIX`, `Fcntl`, `Digest::MD5`

External tool: `ledger` CLI (used via subprocess in `Ledger::_loadFromCLI` to populate transactions from an existing `.dat` file, unless a fresh Storable object cache exists)

## Running the Tests

```sh
cd Ledger.pm/t
perl run_tests.pl          # run all tests, print summary
perl -I.. test_fr001.pl   # run a single test
```

Tests must be run from the `t/` directory so they can find fixture files by relative path.
Each `test_*.pl` exits 0 on pass and 1 on failure. `run_tests.pl` runs all of them and
prints a one-line-per-test summary; on failure it re-prints the full output of failing tests.

### Test inventory

| File | Covers |
|------|--------|
| `test_fr001.pl` | `scheduleEdit()` / `scheduleAppend()` unit tests (FR-001) |
| `test_transfer.pl` | Transfer matching: half-transfer completion, manually-entered transfer, expense with bank account at posting[1] |
| `test_issue4.pl` | Issue 4a: pending→cleared not left in place; Issue 4b: CC import doesn't replace Checking split |
| `test_issue5.pl` | Issue 5: pending transaction moved to cleared section (not overwritten in place) |
| `test_bug010.pl` | BUG-010: two same-date/same-amount CSV rows without FITID both imported (no collision); IDs in `CSV-{hash}` format; second import deduplicates correctly |
| `test_bug010_ofx.pl` | BUG-010 (OFX): OFX transactions written with `OFX-{FITID}` prefix (not account-initials); second import deduplicates correctly |
| `test_bug011.pl` | BUG-011: balance assertion written even when `@append` is empty (all transactions deduplicated) |
| `test_bug014.pl` | BUG-014: date comment not written when only balance entries added and `@append` is empty |
| `test_fr013_ofx.pl` | FR-013: OFX parser — 2 transactions (payee, qty, date, check number), LEDGERBAL balance assertion |
| `test_fr013_ofx_inv.pl` | FR-013: OFX investment — INVBUY with deferred ticker fixup via `stop()`, INVPOS balance assertion |
| `test_bug009_inv.pl` | BUG-009 (investment): LEDGERNAME overrides filename for INVBUY account and INVPOS balance; `stop()` appends `:TICKER` |
| `test_fr013_plaid.pl` | FR-013: Plaid JSON — `ledger_name` override, cleared vs pending state, negated amounts, balance assertion |
| `test_fr013_plaid_inv.pl` | FR-013: Plaid investment — `addinvestments`, commodity/cost, per-security account name, balance assertion |
| `test_fr013_teller.pl` | FR-013: Teller JSON — institution+name account derivation, depository sign, balance assertion |
| `test_fr014.pl` | FR-014: state-aware insertion — single-file ordering (cleared before pending before uncleared) and multi-file routing to correct sub-files |
| `test_bug015.pl` | BUG-015: Bayesian classifier predicts `Equity:Transfers:Visa` from training data, no handler needed |
| `test_bug016.pl` | BUG-016: first pending tx (at `cleared_pos`) cleared to correct position, not EOF |
| `test_bug017.pl` | BUG-017: investment OFX with multiple commodities and mixed `INV401KSOURCE` (PRETAX/MATCH) yields one balance assertion per commodity×source, not one per commodity |
| `test_bug019.pl` | BUG-019: empty ledger file and pending-only ledger file both handled correctly — transactions written, cleared inserted before pending |
| `test_fr020_fidelity.pl` | FR-020: `Ledger::CSV::Fidelity->config(account_map =>)` — keyed by account name (e.g. `"Individual - TOD (...1234)"`), behaviour-identical to FR-015 inline config |
| `test_fr020_hsa.pl` | FR-020: `Ledger::CSV::HSA->config()` — behaviour-identical to FR-016 inline config |
| `test_fr019.pl` | FR-019: CSV auto-detection — `export-2026-03.csv` (no config key match) fingerprinted to `Ledger::CSV::HSA` via `CSV::detect()`; `#LedgerName:` skipped before header read |
| `test_fr020_coinbase.pl` | FR-020: `Ledger::CSV::Coinbase->config()` — Buy/Sell (commodity+cost), Rewards Income (commodity, no cost) |
| `test_fr023.pl` | FR-023: OO parser interface — raw parse via `Ledger::OFX->new->parse` and `Ledger::CSV::HSA->new->parse`; full import via `$ledger->importCallback`; `type()`, `account()`, `account_map()` instance methods on all CSV submodules |
| `test_bug025.pl` | BUG-025: real Fidelity exports — blank preamble lines skipped before header; `Type=Cash` not appended to account name; trailing disclaimer not parsed; 3 rows imported correctly |
| `test_bug013.pl` | BUG-013/BUG-005: Plaid absence scan — orphaned pending with cleared match deleted + note added (scenario A); orphaned pending with no match warned and left in place (scenario B) |
| `test_bal_inline.pl` | Inline balance assertion on cash accounts: last cleared posting gets `= $x.xx` stamped inline; uses bug016 fixtures |
| `test_bal_inline_inv.pl` | Inline balance assertion on investment accounts: last INVBUY posting gets `= N TICKER` stamped inline; uses bug017 (401k) fixtures |

### Fixture files

Each test works on a copy of its fixtures in a temporary directory so originals are never modified.

| Fixture | Used by |
|---------|---------|
| `transfer.ldg`, `Visa-2026-03.csv`, `Checking-2026-03.csv` | `test_transfer.pl`, `test_fr001.pl` |
| `issue4a.ldg`, `issue4a.csv` | `test_issue4.pl` (4a) |
| `issue4b.ldg`, `issue4b-Visa.csv`, `issue4b-Checking.csv` | `test_issue4.pl` (4b) |
| `issue5.ldg`, `issue5.csv` | `test_issue5.pl` |
| `bug010.ldg`, `bug010.csv` | `test_bug010.pl` |
| `bug010.ofx`, `fr013_base.ldg` | `test_bug010_ofx.pl` |
| `bug011.ldg`, `bug011.csv` | `test_bug011.pl` |
| `bug014.ldg`, `bug014.csv` | `test_bug014.pl` |
| `fr013_base.ldg` | all `test_fr013_*.pl` tests (shared minimal ledger) |
| `fr013.ofx` | `test_fr013_ofx.pl` |
| `fr013_ofx_inv.ofx` | `test_fr013_ofx_inv.pl` |
| `fr013_ofx_inv_named.ofx` | `test_bug009_inv.pl` |
| `fr013_plaid.json` | `test_fr013_plaid.pl` |
| `fr013_plaid_inv.json` | `test_fr013_plaid_inv.pl` |
| `fr013_teller.json` | `test_fr013_teller.pl` |
| `fr014_single.ldg` | `test_fr014.pl` (single-file scenario) |
| `fr014_cleared.ldg`, `fr014_pending.ldg`, `fr014_uncleared.ldg` | `test_fr014.pl` (multi-file scenario) |
| `bug015.ldg`, `bug015.csv` | `test_bug015.pl` |
| `bug016.ldg`, `bug016.csv` | `test_bug016.pl` |
| `fr013_ofx_401k.ofx` | `test_bug017.pl` |
| `bug019_empty.ldg`, `bug019_pending.ldg`, `bug019.csv` | `test_bug019.pl` |
| `fr020_coinbase.csv` | `test_fr020_coinbase.pl` |
| `fr016_hsa.csv`, `fr013_base.ldg` | `test_fr019.pl` (reused from FR-016/FR-013) |
| `fr013.ofx`, `fr016_hsa.csv`, `fr015_fidelity.csv`, `fr013_base.ldg` | `test_fr023.pl` (reused from FR-013/FR-015/FR-016) |
| `bug025_fidelity.csv`, `fr013_base.ldg` | `test_bug025.pl` |
| `bug013.ldg`, `bug013.json` | `test_bug013.pl` |
| `bug016.ldg`, `bug016.csv` | `test_bal_inline.pl` (reused from BUG-016) |
| `fr013_base.ldg`, `fr013_ofx_401k.ofx` | `test_bal_inline_inv.pl` (reused from BUG-017) |

There is no `Makefile` or CI configuration.

## Architecture

### Module Responsibilities

| Module | Role |
|--------|------|
| `Ledger.pm` | Core orchestrator: loads existing ledger (via Storable cache or `ledger csv`), manages transaction list, runs import pipeline, writes changes back |
| `Ledger/Transaction.pm` | Single transaction: date/state/payee/postings, file byte-position tracking (`bpos`/`epos`/`edit_pos`), matching logic |
| `Ledger/Posting.pm` | Single posting (account + amount + commodity), serialization. When `$posting->{add_assert}` is set, `toString` appends an inline balance assertion (`= $x.xx` for dollar postings, `= N TICKER` for commodity postings) using `$posting->{assert}` as the value. |
| `Ledger/CSV.pm` | Parses CSV bank statement files; `detect($header)` returns matching institution module; `new($file, $args, %opts)` — factory: when `$args` is undef, peeks the header and returns the appropriate sub-object (`$mod->new($file, %opts)`); `parse($cb)` OO interface; loaded lazily by `fromStmt` |
| `Ledger/CSV/Fidelity.pm` | Fidelity brokerage CSV: `fingerprint()` + `config(account_map =>)` (keyed by account name) + `new`/`parse` OO interface; `type()` returns `'Fidelity'`; `account($val)` / `account_map($val)` instance setters |
| `Ledger/CSV/HSA.pm` | HSA/benefit CSV: `fingerprint()` + `config()`, `running_balance` for BAL assertion + `new`/`parse` OO interface; `type()` returns `'HSA'`; `account($val)` instance setter |
| `Ledger/CSV/Coinbase.pm` | Coinbase Advanced Trade CSV: `fingerprint()` + `config()`, account from `#LedgerName:` + `new`/`parse` OO interface; `type()` returns `'Coinbase'`; `account($val)` instance setter |
| `Ledger/OFX.pm` | Parses OFX/QFX bank statement files; `new($file)` + `parse($cb)` OO interface |
| `Ledger/JSON.pm` | Dispatches JSON to Plaid or Teller submodule; `new($file)` + `parse($cb)` OO interface |
| `Ledger/JSON/Plaid.pm` | Parses Plaid API exports (banking + investment) |
| `Ledger/JSON/Teller.pm` | Parses Teller API exports |
| `Ledger/XML.pm` | Parses Ledger-CLI XML export format |

### Import Pipeline

`fromStmt($stmt, \%handlers, \%csv_config, \%module_opts)` drives the import. `$stmt` may be either a filename or a pre-constructed parser object. When a filename is given, it infers the account name from the filename (prefix before the first `-`), calls `importCallback($account, $handlers)` to build the routing closure, then delegates to the appropriate OO parser (`Ledger::OFX->new->parse`, `Ledger::CSV->new->parse`, or `Ledger::JSON->new->parse`). For CSV files, `fromStmt` calls `Ledger::CSV->new($stmt, $csv->{$account}, %module_opts)`. When `$csv->{$account}` is undef (filename prefix has no matching key), `CSV->new` acts as a factory: it peeks the header line (skipping any `#LedgerName:` directive), calls `detect()`, and returns the matched sub-object (`$mod->new($file, %opts)`). `%module_opts` is the optional 4th argument to `fromStmt`; pass e.g. `account_map => \%map` there when auto-detecting multi-account formats like Fidelity. When `$stmt` is an object, `fromStmt` calls `$stmt->account()` (if the method exists) to obtain the account name, then calls `$stmt->parse($callback)` directly — `%csv_config` and `%module_opts` are ignored in this path. Callers who need to drive imports without going through `fromStmt` can call `importCallback` directly and pass the result to any parser's `parse()` method.

Each parsed transaction is routed through `addStmtTran`, which:
1. Deduplicates via ID cache (`makeid()` generates a stable key from account initials + FITID or date+amount)
2. Looks up a handler (code ref or hashref with `payee`/`transfer` keys) by account+payee, falling back to the payee description cache (`YAML::Tiny`-persisted)
3. Matches against existing uncleared transactions using `Transaction::balance()` — a scoring function based on date proximity, amount difference, payee similarity, check number, and pending ID
4. Only accepts transactions within 90 days and after 2024-03-08

### Inline Balance Assertions

When writing new cleared transactions, `update_file` calls `annotate_balance_assertions` to stamp the last posting for each account/commodity with `add_assert` and `assert` fields. `Posting::toString` then appends `= $x.xx` (dollar) or `= N TICKER` (commodity) inline on that posting, giving a ledger-verifiable balance assertion without a separate transaction.

`$self->{balance}` is keyed by account+commodity. For OFX investment imports, `OFX::stop()` resolves CUSIP codes to tickers by updating posting objects in-place, but does not re-key the balance hash. `_rekey_balance()` is called after each OFX parse to rebuild the hash from the (now-correct) posting fields, keeping the keys valid before `update()` runs.

### Transfer Matching

`transfer($transaction, $tag)` implements double-entry transfer pairing. Unmatched sides are parked under `Equity:Transfers:$tag` until the other side arrives (matched by date within 5 days and opposing amount).

### Auto-Categorization

`gentable()` builds a frequency table: `source_account → payee → destination_account`. Called automatically at construction, used by `Transaction::balance` when no explicit handler provides a category. Falls back to `Income:Miscellaneous` or `Expenses:Miscellaneous`.

### Object Cache

`Ledger->new` serializes the fully-built object to `$file.store` (via `Storable`) after a cold load. On the next construction with the same file, if `$file.store` is newer than `$file`, the cached object is returned immediately — no `ledger csv` subprocess, no CSV parsing.

**Cache invalidation**: any caller that writes to the ledger file (via `update()`) must unlink `$file.store` afterwards to force a rebuild on the next load. Failure to do so means subsequent scripts in the same pipeline will read a stale object.

### File-Based In-Place Editing

Transactions track their byte positions in source `.dat` files (`bpos`, `epos`). `update()` writes to a `$file.tmp$$` temp file first, then renames it into place; a `.bak` is kept as a safety copy. New transactions are appended at the appropriate insertion point (`cleared_pos`, `pending_pos`, or `uncleared_pos`); in-place edits overwrite the exact byte range of the original transaction.

### Account Resolution

Account numbers are loaded from a pipe-delimited file (`accounttab`):
```
1234 | Assets:Checking:MyBank
```
`getaccount()` resolves 4-digit suffixes from statement data to full account names.

## Key Conventions

- All objects are hashref-based, blessed into their package with `bless $self, $class`
- Dates are stored as Unix timestamps internally; formatted with `strftime` for output
- Transaction state values: `'cleared'` (`*`), `'pending'` (`!`), or `''` (uncleared)
- `edit_pos == -1` means append; `edit_pos >= 0` means in-place update at that byte offset
- Transaction IDs are stored in ledger using the tag `ID:` (hardcoded)

## Potential Future CSV Modules

Institutions that lack OFX export and are not reliably covered by Plaid or Teller, making them
good candidates for dedicated `Ledger::CSV::*` modules:

| Institution | Notes |
|-------------|-------|
| **Apple Card** | CSV only, no OFX, no Plaid. Clean format: `Transaction Date`, `Clearing Date`, `Description`, `Merchant`, `Category`, `Type`, `Amount (USD)`. |
| **Charles Schwab** | Plaid covers checking but brokerage history is spotty. CSV has 2–3 preamble lines (account name/number) before the column header — similar to Fidelity. Key columns: `Date`, `Action`, `Symbol`, `Quantity`, `Price`, `Fees & Comm`, `Amount`. |
| **Vanguard** | Weak Plaid coverage for brokerage/retirement. CSV has a date-range line before column names; mixes mutual fund and ETF rows with different semantics. |
| **PayPal** | Plaid shows only a summary; full CSV has `Currency`, `Balance`, `Type` (payment/transfer/refund) and multi-currency rows that need collapsing. |
| **Kraken** | Natural companion to Coinbase. Uses a `Ledgers` export with `txid`, `type` (trade/transfer/staking/earn), `asset`, `amount`, `fee`. Staking rewards are a distinctive row type. |
| **TSP** | Federal Thrift Savings Plan — zero Plaid/Teller coverage, no OFX. Simple CSV but unique fund codes (G/F/C/S/I/L funds). |

## Full API Reference

See `Ledger-docs.md` for complete method signatures and examples.
