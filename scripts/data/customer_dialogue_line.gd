extends Resource
class_name CustomerDialogueLine

## A single flavor/small-talk line a customer may say while being served at
## the Teller desk (Phase 6b). Built in code (see customer_dialogue_data.gd)
## rather than loaded from .tres files, matching InterviewQuestion/
## LoanApplication.
##
## mood is captured now even though nothing reacts to it yet, so a future
## complaint/dispute mechanic (6c) can key off it without retrofitting it
## onto every existing line.

enum Mood { FRIENDLY, NEUTRAL, IMPATIENT }

@export var text: String = ""
@export var mood: Mood = Mood.NEUTRAL
