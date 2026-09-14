extends RefCounted
class_name CustomerDialogueData

## Static provider for the Teller desk's customer small-talk pool (Phase
## 6b). Kept separate from CustomerDialogueLine (the data shape) so the
## actual line content can grow independently of it, mirroring
## InterviewQuestionsData/LoanApplicationsData.
##
## Flavor text only — nothing here has gameplay consequences yet (that's
## 6c's job).

static func get_lines() -> Array[CustomerDialogueLine]:
	return [
		_line("Lovely weather today, isn't it?", CustomerDialogueLine.Mood.FRIENDLY),
		_line("I've been banking here for years, you all do a great job.", CustomerDialogueLine.Mood.FRIENDLY),
		_line("Thank you so much for your help, I really appreciate it.", CustomerDialogueLine.Mood.FRIENDLY),
		_line("Your branch has the friendliest staff, honestly.", CustomerDialogueLine.Mood.FRIENDLY),
		_line("Busy day today, huh?", CustomerDialogueLine.Mood.NEUTRAL),
		_line("Just here for a quick transaction.", CustomerDialogueLine.Mood.NEUTRAL),
		_line("Do you know if it's supposed to rain later?", CustomerDialogueLine.Mood.NEUTRAL),
		_line("I think I was here last week too, or maybe that was another branch.", CustomerDialogueLine.Mood.NEUTRAL),
		_line("Sorry if I seem frazzled, it's just been one of those days.", CustomerDialogueLine.Mood.NEUTRAL),
		_line("This line was so long, I almost left.", CustomerDialogueLine.Mood.IMPATIENT),
		_line("Can we please make this quick? I'm on my lunch break.", CustomerDialogueLine.Mood.IMPATIENT),
		_line("I've been waiting forever, I hope this doesn't take long.", CustomerDialogueLine.Mood.IMPATIENT),
		_line("Every time I come here there's a wait. Every single time.", CustomerDialogueLine.Mood.IMPATIENT),
		_line("I need to get this done fast, I've got somewhere to be.", CustomerDialogueLine.Mood.IMPATIENT),
	]

static func _line(text: String, mood: CustomerDialogueLine.Mood) -> CustomerDialogueLine:
	var line := CustomerDialogueLine.new()
	line.text = text
	line.mood = mood
	return line
