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
