extends Resource
class_name CustomerComplaint

## A complaint scenario a "complaint" customer (Phase 6c) presents when
## served, in place of a regular flavor line — see CustomerQueue's
## COMPLAINT_CHANCE, which decides at spawn time whether a customer gets
## this instead of a CustomerDialogueLine. Built in code (see
## customer_complaints_data.gd), the same Resource + static-provider
## pattern as InterviewQuestion/InterviewQuestionsData.

@export var complaint_text: String = ""
@export var responses: Array[ComplaintResponse] = []
