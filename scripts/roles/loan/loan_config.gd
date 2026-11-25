extends RefCounted
class_name LoanConfig

## The Loan Officer role's own numbers (ROLE_BOUNDARIES.md: each role's
## numbers live in its own config). Shared slot-system values are in
## DaySchedule.

## Applications one work slot brings to Loan Desk 1 (decisions 2 and 17;
## LoanSlotAdapter).
const APPLICATIONS_PER_SLOT: int = 1

# --- multi-day applications: files waiting for documents (LoanPipeline) ----

## Files that may be open at once (waiting, or returned and not yet decided).
const PIPELINE_MAX: int = 3
## Times one file may ask for more documents.
const MAX_REQUESTS_PER_FILE: int = 2

## Business days from the request to the due day: one item asked for takes
## DUE_DAYS_MIN, each further item one more day, never more than DUE_DAYS_MAX.
const DUE_DAYS_MIN: int = 2
const DUE_DAYS_MAX: int = 5

## When a file's documents come back (against its due day). The three
## shares add up to 1.
const RETURN_ON_TIME: float = 0.70
const RETURN_LATE: float = 0.20
const RETURN_NEVER: float = 0.10
## A late file comes back this many business days after its due day
## (first and last, both possible).
const LATE_DAYS_MIN: int = 1
const LATE_DAYS_MAX: int = 2
## A file that hasn't come back this many business days after its due day
## expires, with no penalty.
const EXPIRES_AFTER_DUE_DAYS: int = 3

## What comes back (the three shares add up to 1): everything asked for,
## everything but one item, or a document that doesn't match what the
## applicant stated.
const QUALITY_COMPLETE: float = 0.75
const QUALITY_INCOMPLETE: float = 0.20
const QUALITY_WRONG: float = 0.05

## The chance that an applicant is truly missing each of the three documents
## that apply only to some applications (the appraisal, the proof of the
## down payment and the letter explaining a late payment or collection). The
## pay stub, the statement and the photo ID are missing when the
## application's own documents say so.
const NEW_ITEM_MISSING_CHANCE: float = 0.08

# --- grading a request for more documents (LoanRequirements.grade_request) ---

## A request whose checklist is exactly right (every truly missing item
## ticked and nothing else): the request's own reward, well under a correct
## final decision (LoanApplication.BEST_DECISION_SCORE, 10), so a request
## followed by that decision (two slots) earns less per slot than deciding a
## good file at once.
const REQUEST_RIGHT_SCORE: int = 3
## Each ticked item that is not missing, and each missing item left unticked.
const REQUEST_WRONG_TICK_SCORE: int = -1
const REQUEST_MISSED_ITEM_SCORE: int = -1
## A request on a file with nothing missing (the whole request, however many
## items were ticked).
const REQUEST_COMPLETE_FILE_SCORE: int = -2
## A request on a file whose problem is a forged or wrong document (the stub
## or statement doesn't show the stated income, the stub is in another
## name, the ID's name or photo doesn't match): more documents can't fix
## that, and Reject naming "could not be verified" is the best answer.
const REQUEST_FORGED_SCORE: int = -3
## Reputation never moves for a request.
const REQUEST_REPUTATION: int = 0

# --- a returned file waiting for a decision (LoanFile, LoanPipeline) -----------

## A returned file not decided within this many business days of the day it
## came back is withdrawn at the start of the next work day.
const DECIDE_WITHIN_DAYS: int = 3
## What a withdrawn file costs (once per file; nothing if it is decided in time).
const WITHDRAWN_SCORE: int = -2
const WITHDRAWN_REPUTATION: int = -1

## A returned file still undecided this many business days after its return
## day is closed quietly at Opening (no penalty, whatever role the player has
## chosen): an applicant doesn't wait for ever. The Loan Officer day rule
## above still comes first.
const ABANDONED_AFTER_DAYS: int = 15

# --- the closing step (LoanClosings, LoanClosing) -----------------------------

## Whether an approval or an accepted counter-offer goes through a closing
## before the loan is booked. Off while the feature is built; a static
## variable, not a constant, so tests can turn it on (the loan suite turns it
## back off after every test). Read by the review screen's decision, nothing
## else: a closing that exists is always dealt with, whatever this says.
static var closings_enabled: bool = false

## Business days from the approval to the closing, by purpose (the loan's
## bigger the longer the paperwork takes). A purpose not listed uses
## CLOSING_DAYS_DEFAULT.
const CLOSING_DAYS: Dictionary[String, int] = {"Auto": 1, "Personal": 1, "Business": 2, "Home": 3}
const CLOSING_DAYS_DEFAULT: int = 1

## The chance a closing has a problem (the same for every closing), and which
## problem (the four shares add up to 1). The career's first closing is always
## clean.
const CLOSING_PROBLEM_CHANCE: float = 1.0 / 7.0
const CLOSING_MIX_TERMS: float = 0.30
const CLOSING_MIX_EXPIRED_ID: float = 0.25
const CLOSING_MIX_NO_SIGNATURE: float = 0.25
const CLOSING_MIX_NEW_DEBT: float = 0.20

## A terms mismatch changes one figure on the final paperwork. These are how
## far: the amount by this share of it (rounded to $100, at least $100), the
## rate by this many percentage points (in quarter points), the payment by
## this share, the term to this share of the approved term (rounded to whole
## years, at least a year).
const MISMATCH_AMOUNT_SHARE: Array[float] = [0.05, 0.15]
const MISMATCH_RATE_POINTS: Array[float] = [0.5, 2.0]
const MISMATCH_PAYMENT_SHARE: Array[float] = [0.08, 0.20]
const MISMATCH_TERM_SHARES: Array[float] = [0.5, 0.75, 1.25]

## An expired ID on closing day expired this many days before it.
const EXPIRED_ID_DAYS: Array[int] = [1, 400]
## A good ID on closing day expires this many days after it.
const VALID_ID_DAYS: Array[int] = [200, 2000]

## New debt: the total debt-to-income with it lands between these (both over
## LoanApplication.STRETCHED_DTI, 43%), but the new payment is never less than
## NEW_DEBT_MIN_SHARE of monthly income (a debt that was already over 43% still
## gets visibly worse). Whole $10 payments, at least NEW_DEBT_MIN_PAYMENT.
const NEW_DEBT_DTI_RANGE: Array[float] = [0.44, 0.50]
const NEW_DEBT_MIN_SHARE: float = 0.03
const NEW_DEBT_MIN_PAYMENT: float = 50.0

## A closing not handled within this many Loan Officer days after its due day
## lapses at the start of the next work day (only days whose recorded role was
## Loan Officer count). It costs what a withdrawn file does
## (WITHDRAWN_SCORE and WITHDRAWN_REPUTATION, never so much Reputation that it
## reaches 0).
const CLOSING_LAPSE_DAYS: int = 3
## Whether a closing that lapses for a good applicant (low risk, documents
## fine) counts as a good applicant turned away (the loan book applies it).
const LAPSED_GOOD_APPLICANT_TURNED_AWAY: bool = true

# --- what a closing is worth (LoanBookManager.fund() and stop()) -------------------

## Funding a closing with nothing wrong with it: the work done, well under a
## correct decision (LoanApplication.BEST_DECISION_SCORE, 10).
const CLOSING_FUND_CLEAN_SCORE: int = 5
## Stopping a closing with a real problem: a good catch.
const CLOSING_STOP_PROBLEM_SCORE: int = 8
const CLOSING_STOP_PROBLEM_REPUTATION: int = 1
## Stopping a closing with nothing wrong with it (a good applicant lost is also
## counted as turned away).
const CLOSING_STOP_CLEAN_SCORE: int = -3
## Funding a closing with a problem: a serious mistake (the loan is booked on
## the unverified odds).
const CLOSING_FUND_PROBLEM_SCORE: int = -10
const CLOSING_FUND_PROBLEM_REPUTATION: int = -2
