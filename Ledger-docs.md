# Ledger Perl Module Documentation

## Overview

The `Ledger` module is a Perl-based personal accounting system that reads, parses, and writes transactions in [Ledger-CLI](https://ledger-cli.org/) format. It supports importing financial data from multiple sources (OFX/QFX, CSV, JSON) and intelligently matches pending transactions against existing ones using heuristic scoring.

---

## Module Structure

| Module | Description |
|--------|-------------|
| `Ledger` | Core ledger object: transaction management, import orchestration, file writing |
| `Ledger::Transaction` | Represents a single transaction with postings, state, and file positions |
| `Ledger::Posting` | Represents a single posting (account + amount) within a transaction |
| `Ledger::CSV` | Parses CSV bank statement files; loaded lazily by `fromStmt` |
| `Ledger::OFX` | Parses OFX/QFX bank statement files |
| `Ledger::JSON` | Dispatches JSON parsing to Plaid or Teller submodules |
| `Ledger::JSON::Plaid` | Parses Plaid API JSON exports (banking + investment accounts) |
| `Ledger::JSON::Teller` | Parses Teller API JSON exports |


---

## `Ledger`

### Constructor

```perl
my $ledger = Ledger->new(
    file       => '/path/to/ledger.dat',   # optional: existing ledger file
    payeetab   => '/path/to/desc.yaml',    # optional: YAML payee description cache
    idtag      => 'ID',                    # optional: tag name for transaction IDs (default: 'ID')
    useCache   => 1,                       # optional: enable Storable object cache ($file.store)
    noClassify => 1,                       # optional: skip gentable() (edit-only callers, no import)
);
```

On construction:

1. Loads the payee description cache (via `YAML::Tiny`; falls back to `Storable` for legacy `desc.dat` files)
2. Loads the account number mapping table
3. Runs `ledger csv` to populate transactions from the existing ledger file
4. Builds the Naive Bayes classifier used for auto-categorization (skipped if `noClassify => 1`)

If `useCache => 1` is passed and a Storable object cache exists at `$file.store` that is newer than `$file`, the cached object is returned immediately (steps 1–4 are skipped). Otherwise, the fully-built object is written to `$file.store` after construction.

**Cache invalidation**: callers that write to the ledger (via `update()`) must unlink `$file.store` afterwards to force a rebuild on the next load.

---

### Methods

#### `addTransaction(%args | $transaction)`

Adds a transaction to the ledger. Accepts either a `Ledger::Transaction` object or named constructor arguments.

```perl
$ledger->addTransaction($transaction_obj);
$ledger->addTransaction($date, $state, $code, $payee, $note);
```

Returns the `Ledger::Transaction` object.

---

#### `addBalance($account, %args | $transaction)`

Records a balance assertion for an account. Only stores the most recent balance per commodity.

```perl
$ledger->addBalance('Assets:Checking', $transaction);
```

---

#### `fromStmt($filename, \%handlers, \%csv_config)`

Imports transactions from a bank statement file. The account name is derived from the filename (the part before the first `-`).

```perl
$ledger->fromStmt('checking-2024-01.ofx', \%handlers);
$ledger->fromStmt('checking-2024-01.csv', \%handlers, \%csv_config);
$ledger->fromStmt('checking-2024-01.json', \%handlers);
```

Supported file types:
- `.ofx` / `.qfx` — OFX/QFX format
- `.csv` — Delimited text (requires CSV config)
- `.json` — Plaid or Teller API export

Each transaction in the file is passed to either `addStmtBal` (for balance records) or `addStmtTran` (for regular transactions).

---

#### `addStmtTran($account, \%handlers, \%stmttrn)`

Processes a single imported transaction. Key behaviors:

- Deduplicates via the transaction ID cache (`$self->{id}`)
- Looks up a handler by account + payee using a cascading strategy: exact payee → desc cache → cleaned payee → token-based fallback (`_token_lookup`)
- Resolves the canonical payee name via desc cache or token-based desc lookup when no handler matched
- Attempts to match against existing uncleared transactions using `Transaction::balance`
- Only adds transactions dated within the last 90 days (and after 2024-03-08)

**Token-based lookup** (`_token_lookup`): tokenizes both the incoming payee and each handler/desc key, then finds the key whose tokens are all present in the payee tokens, preferring the most specific (most-token) match. This handles intermediary prefixes like `SQ *` or `PAYPAL *` transparently — a handler keyed on `"blue bottle"` matches `"SQ *BLUE BOTTLE 123456"` without needing a separate entry.

**Handlers** can be:
- A code reference: `sub { my $t = shift; ... return $t }`
- A hash ref with `payee` and/or `transfer` keys for simple remapping

---

#### `addStmtBal($account, \%balance)`

Processes a balance record from a statement. Creates a balance-assertion posting.

---

#### `transfer($transaction, $tag)`

Implements double-entry transfer matching. When two accounts transfer funds between each other (e.g., a checking payment to a credit card), this method pairs the two sides using `Equity:Transfers:$tag` as an intermediary until both sides have been seen.

```perl
$ledger->transfer($transaction, 'Visa');
```

The transfer store (`$ledger->{transfer}`) is a hash keyed by `"$tag-$amount"`. Each entry holds a list of `[$transaction, $posting]` pairs waiting for their counterpart.

**Matching condition**: two sides are paired when `abs(cost_A + cost_B) < 0.0001` (opposing signs) and the transaction dates are within 5 days. The amount key uses the absolute value, so both sides index under the same key regardless of sign.

**Same-day match** (`datediff < 1`): the existing transaction is merged in-place — its state is promoted to cleared, posting[1] is replaced with the incoming posting, and the payee is updated if the incoming one is longer. The incoming transaction is discarded (returns `undef`).

**Cross-day match** (`1 ≤ datediff ≤ 5`): both transactions are kept. An `Equity:Transfers:$tag` posting is appended to the incoming transaction and it is added to the ledger normally.

**No match**: the incoming transaction is parked in the transfer store with an `Equity:Transfers:$tag` posting appended, awaiting its counterpart from a future import.

When a match is found and the existing (parked) transaction's `Equity:Transfers:$tag` posting does not already hold the correct account, it is rewritten — but only if the transaction is not already cleared (cleared transactions are left unchanged).

---

#### `getTransactions($filter)`

Returns a list of transactions matching the given filter.

```perl
my @all        = $ledger->getTransactions();
my @cleared    = $ledger->getTransactions('cleared');
my @uncleared  = $ledger->getTransactions('uncleared');
my @balances   = $ledger->getTransactions('balance');
my @editable   = $ledger->getTransactions('edit');
my @custom     = $ledger->getTransactions(sub { $_[0]->{payee} =~ /Amazon/ });
```

---

#### `gentable()`

Builds an internal frequency table mapping `source account → payee → destination account`. Used by `Transaction::balance` for probabilistic auto-categorization. Called automatically during construction.

---

#### `toString()` / `toString2($filter)`

Serializes transactions back to Ledger-CLI text format.

- `toString()` — outputs all transactions and balances sorted by date
- `toString2()` — outputs cleared transactions, then balance assertions, then a `; ----UNCLEARED-----` separator, then uncleared transactions. Accepts an optional filter (same values as `getTransactions`).

---

#### `update()`

Writes all modified transactions back to their source files. For each file:
- Transactions with `edit_pos >= 0` are updated in-place
- New transactions (with `edit_pos == -1`) are appended at the OFX insertion point
- Balance assertions are written alongside new transactions
- A backup (`.bak`) is made before overwriting

Also persists the payee description cache via `YAML::Tiny`.

---

#### `fromXML($xml_string)`

Populates the ledger from a Ledger-CLI XML export string.

```perl
$ledger->fromXML($xml_string);
```

---

#### `_loadFromCLI($file)`

Private. Called by `new()`. Runs `ledger csv` with a custom prepend format and populates the ledger object with the resulting transactions and postings.

Custom fields extracted per posting:

```
transaction_id, file, bpos, epos, xnote, ID_tag, price, date,
code, payee, account, commodity, amount, state, note
```

**Transfer store population**: pre-populates `$self->{transfer}` so that the current import session can match against existing half-transfers. Two kinds of postings are added:

- `Equity:Transfers:$tag` postings — parked placeholders from a previous session. A negated copy (sign-flipped quantity) is stored so that an incoming same-sign posting cancels it.
- `Assets` or `Liabilities` postings with no `ID:` note — transfers where one side was imported without an ID (e.g. a manually-entered transfer). The last component of the account name is used as the tag, and a negated copy is stored.

In both cases the negated copy ensures `transfer()`'s matching condition (`abs(cost_A + cost_B) < 0.0001`) evaluates to zero when the opposing side arrives.

---

### Internal Helpers

#### `makeid($account, \%stmttrn)`

Generates a stable deduplication key for a statement transaction. Format:

```
{AccountInitials}[-{salt}]-{fitid}
  or
{AccountInitials}[-{salt}]-{YYYY/MM/DD}+${amount}
```

A `!` is appended for pending transactions.

---


## `Ledger::Transaction`

Represents a single Ledger-CLI transaction.

### Fields

| Field | Description |
|-------|-------------|
| `date` | Unix timestamp of the transaction date |
| `state` | `'cleared'`, `'pending'`, or `''` |
| `code` | Check number or other reference code |
| `payee` | Payee/description string |
| `note` | Transaction-level note/memo |
| `postings` | Array of `Ledger::Posting` objects |
| `file` | Source `.dat` file path |
| `bpos` | Byte offset of transaction start in source file |
| `epos` | Byte offset of transaction end in source file |
| `edit` | Target file for writing changes |
| `edit_pos` | Byte offset for in-place edit; `0` = position not yet resolved (set by `findtext` during `update()`); `-1` = append at OFX insertion point |
| `edit_end` | End offset of the original text to be replaced |
| `transfer` | Transfer tag if this is part of a transfer pair |
| `aux-date` | Secondary/effective date |

### Constructor

```perl
my $t = Ledger::Transaction->new($date, $state, $code, $payee, $note);
```

### Methods

#### `addPosting($account, $quantity, $commodity, $cost, $note)`

Appends a posting to the transaction. Accepts either a `Ledger::Posting` object or raw fields.

#### `getPosting($index)`

Returns the posting at `$index`. Negative indices work as in Perl arrays (e.g., `-1` is the last posting).

#### `setPosting($index, $posting)`

Replaces the posting at `$index`.

#### `getPostings()`

Returns all postings as a list.

#### `toString()`

Serializes the transaction to Ledger-CLI text. If the transaction has a cached `text` field and has not been edited, returns the original text verbatim.

#### `findtext($fh)`

Locates the exact byte range of this transaction in its source file by reading backwards from the first posting's `bpos`. Populates `bpos`, `epos`, and `text`.

#### `balance($table, @pending_transactions)`

Attempts to auto-complete a transaction that has only one posting. 

1. Calls `checkpending` to see if it matches an existing uncleared transaction
2. If no match, uses the frequency table to predict the destination account
3. Falls back to `Income:Miscellaneous` or `Expenses:Miscellaneous`
4. Returns a transfer tag if the destination is an asset or liability account

#### `checkpending(@pending_transactions)`

Finds the best-matching uncleared/pending transaction from `@pending_transactions` using `distance()` scoring. Returns `1` on match (score < 1.0) and merges; returns `0` otherwise.

**Transfer block**: if `$self->{transfer}` is set (the incoming transaction is half of a transfer), the non-matching posting of the candidate is inspected. If that posting is not already an `Equity:Transfers:*` account and not a real `Assets` or `Liabilities` account, the candidate is rewritten: the matched posting is replaced with `Equity:Transfers:$tag` and the method returns early without fully merging. This handles the case where an uncleared transaction was manually categorised to a placeholder account before the transfer was recognised. Real asset/liability accounts on the other side are left intact.

**Quantity blanking**: after the matched posting is updated with the imported data, the last posting of the candidate has its quantity cleared (so ledger computes the balance automatically). The blank is applied only when the matched posting is not the last one — if the match is at the final posting index the imported amount is preserved as-is.

**Edit position**: how the merged transaction is written back to disk depends on which side has a source file:
- If the incoming transaction has a `file` (e.g., a previously-imported but uncleared entry), it is rewritten at that file's byte position.
- If only the candidate has a `file` (the common case: a new CSV/OFX import matched an existing uncleared entry), the candidate's ledger-file position is used for an in-place overwrite.
- If neither has a `file`, the merged transaction is appended.

#### `distance($other_transaction)`

Computes a heuristic match score between two transactions. Lower is better; scores below 1.0 are considered matches. The score combines:
- Date proximity (5-day half-weight window)
- Amount difference (10x weight)
- Payee token recall: fraction of ledger payee tokens found in statement payee tokens (1 - recall contributes to distance; works correctly for intermediary prefixes like "SQ *" or "PAYPAL *")
- Check number equality (gold standard: returns 0 immediately on match)
- Pending ID match (returns 0 immediately on match)

---

## `Ledger::Posting`

Represents a single line item within a transaction.

### Fields

| Field | Description |
|-------|-------------|
| `account` | Full account name (e.g., `Assets:Checking:MyBank`) |
| `quantity` | Numeric amount |
| `commodity` | Currency or ticker symbol (default: `$`) |
| `cost` | Total cost in `$` for non-dollar commodities; `'BAL'` for virtual balance assertions (`[account] = $X`); `'ASSERT'` for real-account balance assertions (`account   = $X`) |
| `note` | Inline note/memo |

### Constructor

```perl
my $p = Ledger::Posting->new($account, $quantity, $commodity, $cost, $note);
```

### Methods

#### `cost()`

Returns the effective dollar cost: `quantity` for `$` postings, `cost` field for commodity postings.

#### `getid()`

Extracts the ID tag value from the posting note. Returns `""` if no `ID: ...` note is present.

#### `toString()`

Serializes the posting to a Ledger-CLI posting line. Handles:
- Dollar amounts: `$0.00` format
- Commodity amounts: `N TICKER @@ $cost` format
- Virtual balance assertions (`cost eq 'BAL'`): `[account]   = $0.00` format
- Real-account balance assertions (`cost eq 'ASSERT'`): `account   = $0.00` format
- Inline notes

---

## `Ledger::CSV`

Loaded lazily by `fromStmt` when a `.csv` statement file is processed. Not loaded during `Ledger->new`.

### `parsefile($file, \%args, $callback)`

Parses a CSV statement file, calling `$callback->(\%transaction)` for each row.

`%args` keys:

| Key | Description |
|-----|-------------|
| `fields` | Ordered array of field names mapping CSV columns to hash keys |
| `header_map` | Hashref `{ field_name => 'Column Header' }`: reads the first non-blank/non-comment line as column headers and builds `fields` from it; mutually exclusive with `fields` |
| `csv_args` | Hashref passed to `Text::CSV->new` |
| `reverse` | If true, negates the quantity (ignored for balance assertions) |
| `running_balance` | Field name whose value is treated as a running balance assertion (stored as `cost='BAL'` row) |
| `process` | Optional coderef called on each row hashref before the main callback |

**Preamble and directives**: before reading data rows, `parsefile` skips any leading blank rows and rows whose first field starts with `#`. A `#LedgerName: <name>` row, if present, sets the `ledgername` key on each emitted row. With `header_map`, the first non-blank/non-`#` row is consumed as the column-header row. Without `header_map`, the file position is reset to the start of that row so it is read as a data row.

**Recognised field names** (others are passed through unchanged):

| Field | Processing |
|-------|------------|
| `date` | Parsed via `str2time`; rows with no valid date are skipped |
| `quantity` | `=` prefix → balance assertion (sets `cost='BAL'`, strips `=`); everything up to and including the last `$` is stripped |
| `payee` | Leading whitespace and `~.*` suffix stripped |
| `account` | Passed through as-is |
| `commodity` | Optional; `Posting::new` defaults to `$` when absent |
| `cost` | Set automatically to `'BAL'` for `=`-prefixed quantities; otherwise passed through |

**Balance assertions**: a quantity beginning with `=` (e.g. `= $95.00` or `=95.00`)
is treated as a balance assertion and routed to `addStmtBal` by the `fromStmt`
callback.  No extra column is needed.

```
2026/02/04,,Checking Balance,= $65.00,Assets:Checking
```

---

## `Ledger::OFX`

### `parsefile($filename, $callback)`

Parses an OFX or QFX file. Calls `$callback->(\%transaction)` for each transaction or balance record.

Handles the following OFX aggregates:

| OFX Element | Handler | Description |
|-------------|---------|-------------|
| `STMTTRN` | `stmttrn` | Bank/card transactions |
| `INVBUY` / `INVSELL` | `inv` | Investment buy/sell |
| `INCOME` | `inv` | Investment income |
| `REINVEST` | `inv` | Dividend reinvestment |
| `LEDGERBAL` | `ledgerbal` | Cash balance assertion |
| `INVBAL` | `invbal` | Investment cash balance |
| `INVPOS` | `invpos` | Investment position (shares held) |
| `SECINFO` | `secinfo` | Security metadata (ticker, price) |
| `ACCTID` | `acctid` | Account identifier |

The callback receives a hashref with these keys:

| Key | Description |
|-----|-------------|
| `date` | Unix timestamp |
| `quantity` | Amount (positive = credit, negative = debit) |
| `payee` | Payee/memo string |
| `id` | OFX `FITID` |
| `number` | Check number (or `'ATM'`) |
| `commodity` | Ticker symbol for investment transactions |
| `cost` | Total dollar cost for investment transactions; `'BAL'` for balances |
| `type` | Transaction or income type |

---

## `Ledger::JSON`

### `parsefile($file, $callback)`

Reads and dispatches a JSON file to the appropriate parser:
- **Hash** root → `Ledger::JSON::Plaid`
- **Array** root → `Ledger::JSON::Teller`

---

## `Ledger::JSON::Plaid`

Parses a Plaid API export JSON file containing `accounts`, `transactions`, `investment_transactions`, and `securities`.

### Account Name Derivation

Account names are derived from Plaid account metadata:

```
Assets:$subtype:$official_name
Liabilities:$subtype:$official_name
```

Names are title-cased, stripped of non-alphanumeric characters (except `:` and space), and `MC` is uppercased.

### Balance Handling

Balance assertions are emitted for each account whose `lasttrans` date is non-zero (i.e., at least one new transaction was imported). The balance is taken from the Plaid `current` balance field, negated for liability accounts.

---

## `Ledger::JSON::Teller`

Parses a Teller API export. The JSON root is an array of account objects, each containing a `transactions` array.

### Account Name Derivation

```
Assets:Current Assets:$institution $account_name
Liabilities:Credit Card:$institution $account_name
```

`USAA` is uppercased; all other names are title-cased.

### Sign Convention

For liability accounts, the sign of transactions is auto-detected from the first transaction: if the first transaction is a `payment` type, the sign logic inverts.

### Running Balance

If a transaction includes a `running_balance` field, it supersedes the account's static balance for the balance assertion.

---

## Balance Assertions

Balance assertions verify that an account's running total matches a known balance at a point in time. Two forms are used:

**Virtual posting** (`cost => 'BAL'`) — used by `addStmtBal` for bank-reported balances:
```
2026/02/02 * Checking Balance
     [Assets:Checking:MyBank Checking]        = $2500.00
```
The bracketed account name makes this a virtual posting; Ledger-CLI asserts the balance without affecting other accounts.

**Real-account assertion** (`cost => 'ASSERT'`) — used for postings on real accounts where the balance should equal a known value after the transaction:
```
2026/02/02 * Electric Bill
     Accounts Payable:Utilities:Electric      = $-85.00
     Expenses:Utilities:Electric
```
No brackets; Ledger-CLI treats this as a normal posting whose amount is implied by the assertion target.

---

### Sources

Balance assertions are generated automatically during statement import whenever the source data includes a reported balance. Each parser signals this by setting `cost => 'BAL'` on the record passed to the callback, which routes it to `addStmtBal` instead of `addStmtTran`.

| Source | Balance Field |
|--------|--------------|
| OFX/QFX — bank/card | `LEDGERBAL` element |
| OFX/QFX — investment cash | `INVBAL` element |
| OFX/QFX — investment positions | `INVPOS` element (one per holding) |
| Plaid | `accounts[].balances.current` |
| Teller | `accounts[].balances.ledger` (or `running_balance` from most recent transaction if present) |

For liability accounts (Plaid and Teller), the balance is negated before storage.

---

### Storage

Balance assertions are kept in `$self->{balance}`, a two-level hash keyed by account then commodity:

```perl
$self->{balance}{'Assets:Checking:MyBank'}{'$'} = $transaction;
```

Only the **most recent** assertion per account/commodity is retained — `addBalance` silently discards any older one for the same account/commodity pair. They are never added to `$self->{transactions}`.

They can be retrieved via:

```perl
my @assertions = $ledger->getTransactions('balance');
```

---

### Output

Balance assertions are written in two contexts:

**`update()`** — written to the ledger file at the OFX insertion point, interleaved with new cleared and uncleared transactions in date order. If there is no OFX insertion point they are appended at the end of the file.

**`toString2()`** — emitted between the cleared transactions and the `; ----UNCLEARED-----` separator.

In both cases the payee is derived from the account name: the last colon-delimited component with `" Balance"` appended (e.g., `"MyBank Checking Balance"`).

---

## Handlers

The `%handlers` hash passed to `fromStmt` controls how incoming statement transactions are categorized and transformed. It is structured as a two-level hash:

```perl
my %handlers = (
    $account_key => {
        $payee_key => $handler,
        ...
    },
    ...
);
```

The outer key is the same account key as the statement filename prefix (e.g., `'1234'`). The inner key is matched against the incoming payee string using the lookup cascade described below.

---

### Handler Lookup Cascade

For each incoming transaction, the handler is resolved in this order:

**1. Exact payee match**
```perl
$handlers{$account}{$payee}
```
The raw payee string from the statement is looked up directly.

**2. Cached description match**
```perl
$handlers{$account}{ $ledger->{desc}{$account}{$payee} }
```
If a prior import already mapped this raw payee to a canonical name for this specific account (via the payee cache), that canonical name is tried as the key.

**3. First-word match**
```perl
$handlers{$account}{ (split /\s+/, $payee)[0] }
```
Only the first whitespace-delimited token of the payee string is used. Useful for payees like `"AMAZON MKTP US*AB12CD"` where the prefix is stable but the suffix varies.

If none of these match, no handler is applied and the transaction proceeds to auto-categorization via the frequency table.

---

### Handler Types

#### Hash ref — payee rename and/or transfer

```perl
'TRANSFER TO SAVINGS' => { payee => 'Savings Transfer', transfer => 'Savings' }
```

| Key | Required | Description |
|-----|----------|-------------|
| `payee` | yes | Replaces the raw statement payee on the created transaction |
| `transfer` | no | Triggers transfer-pairing logic with this tag (see `transfer()`) |

The `payee` rename happens **before** the transaction is constructed, so the canonical name is what gets stored in the ledger and in the payee cache.

If `transfer` is set, `addStmtTran` calls `$ledger->transfer($transaction, $tag)` immediately after construction, bypassing auto-categorization entirely. The transaction will either be paired with its counterpart from another account or parked under `Equity:Transfers:$tag` to await it.

#### Code ref — full control

```perl
'WHOLE FOODS' => sub {
    my $transaction = shift;
    $transaction->addPosting('Expenses:Groceries');
    return $transaction;
}
```

The code ref receives the partially-constructed `Ledger::Transaction` object, which at this point has:
- Its date, state, code, and payee set
- Exactly one posting (the source account with amount and `ID:` note)

The code ref **must** return the transaction object, or `undef` to suppress the transaction entirely (it will not be added to the ledger). It may add postings, modify fields, or call `$ledger->transfer()` manually.

Note that after the code ref returns, auto-categorization (`Transaction::balance`) still runs if the transaction has only one posting — so the code ref only needs to add a second posting if it wants to override the automatic categorization.

---

### Payee Cache Interaction

When a statement transaction matches an existing ID in `$ledger->{id}`, it is a duplicate and skipped — but before returning, `addStmtTran` updates the payee description cache:

```perl
$ledger->{desc}{$account}{$raw_payee} = $canonical_payee;
```

This means that on subsequent imports, previously seen raw payees are automatically mapped to their canonical names on a per-account basis. Two accounts that share the same raw payee string (e.g. `PAYMENT THANK YOU` on both a Visa and an MC statement) each maintain independent mappings and will resolve to different canonical names. The cache is persisted across runs via `YAML::Tiny` when `update()` is called.

Existing `desc.yaml` files in the old flat format (string values at the top level) are automatically detected on load and treated as a read-only `__global__` fallback. New entries are always written account-specifically; global entries are never reinforced, so the cache migrates naturally over subsequent imports.

---

### Handler Example

```perl
my %handlers = (
    '1234' => {
        # Exact match with transfer pairing
        'TRANSFER TO SAVINGS' => { payee => 'Savings Transfer', transfer => 'Savings' },

        # First-word match catches "AMAZON MKTP US*..." variants
        'AMAZON' => { payee => 'Amazon' },

        # Code ref for custom categorization
        'WHOLE FOODS' => sub {
            my $t = shift;
            $t->addPosting('Expenses:Groceries');
            return $t;
        },

        # Return undef to suppress a transaction entirely
        'VOID CHECK' => sub { return undef },
    },
    '5678' => {
        'AUTOPAY PAYMENT' => { payee => 'Credit Card Payment', transfer => 'CreditCard' },
    },
);
```

---

## File Format Notes

### Ledger-CLI Text Format

Transactions are written in standard Ledger-CLI format:

```
2024/03/15 * (1234) Whole Foods Market     ; optional note
     Assets:Checking:MyBank                  $-87.43
     Expenses:Groceries
```

- States: `*` = cleared, `!` = pending, ` ` = uncleared
- Balance assertions use `= $amount` syntax
- Commodity postings use `N TICKER @@ $cost` syntax

### Statement Filename Convention

`fromStmt` derives the account key from the filename by stripping everything from the first `-` onward, then any leading directory path, then the extension:

```
{account_key}-{anything}.{ext}

1234-2024-03.ofx       → account key = "1234"
1234-20240315.csv      → account key = "1234"
/path/to/1234-mar.qfx  → account key = "1234"
```

The extracted key is used to look up handlers in `%handlers` and, for CSV files, to find the format config in the `%csv` hash passed to `fromStmt`. For **CSV files**, the key must be present as a top-level key in `%csv`, since the CSV format and field layout is account-specific:

```perl
my %csv = (
    '1234' => {
        fields   => [qw(date payee quantity)],
        reverse  => 1,
        csv_args => { sep_char => ',' },
    },
);
$ledger->fromStmt('1234-2024-03.csv', \%handlers, \%csv);
```

If the key is not found in `%csv`, `parsefile` will be called with an undefined args hashref and will likely fail.

---

## Usage Example

```perl
use Ledger;

# Load existing ledger and payee cache
my $ledger = Ledger->new(
    file     => 'personal.dat',
    payeetab => 'desc.yaml',
);

# Define handlers for known payees
my %handlers = (
    '1234' => {
        'AMAZON'       => { payee => 'Amazon' },
        'TRANSFER OUT' => { payee => 'Transfer', transfer => 'Savings' },
        'Whole Foods'  => sub {
            my $t = shift;
            $t->addPosting('Expenses:Groceries');
            return $t;
        },
    },
);

# CSV config keyed by the same account key as the filename prefix
my %csv = (
    '5678' => {
        fields   => [qw(date payee quantity)],
        reverse  => 1,
        csv_args => { sep_char => ',' },
    },
);

$ledger->fromStmt('1234-2024-03.ofx', \%handlers);
$ledger->fromStmt('5678-2024-03.csv', \%handlers, \%csv);
$ledger->fromStmt('1234-2024-03.json', \%handlers);

# Write changes back to the ledger file
$ledger->update();

# Or dump to stdout
print $ledger->toString2();
```

---

## Dependencies

| Module | Purpose |
|--------|---------|
| `Storable` | Object cache (`$file.store`) and legacy `desc.dat` migration fallback |
| `YAML::Tiny` | Persist payee description cache (`desc.yaml`) |
| `Text::CSV` | Parse CSV files |
| `Date::Parse` | Parse date strings to Unix timestamps |
| `JSON` | Parse Plaid/Teller JSON exports |
| `POSIX` | `strftime` for date formatting |
| `Fcntl` | File seek constants |
| `Data::Dumper` | Debugging |
