extends RefCounted
class_name TellerConfig

## The Teller role's own numbers (ROLE_BOUNDARIES.md: each role's numbers
## live in its own config). Shared slot-system values are in DaySchedule.

## Customers the player's line brings in one work slot (decisions 2 and 17;
## TellerSlotAdapter).
const CUSTOMERS_PER_SLOT: int = 2
