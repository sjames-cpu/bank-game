extends RefCounted
class_name LoanConfig

## The Loan Officer role's own numbers (ROLE_BOUNDARIES.md: each role's
## numbers live in its own config). Shared slot-system values are in
## DaySchedule.

## Applications one work slot brings to Loan Desk 1 (decisions 2 and 17;
## LoanSlotAdapter).
const APPLICATIONS_PER_SLOT: int = 1
