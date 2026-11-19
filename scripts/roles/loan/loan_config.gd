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
