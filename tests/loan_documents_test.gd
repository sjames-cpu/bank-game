extends GdUnitTestSuite

## Loan applicants' documents (LoanApplicantGenerator.issue_documents()) and
## how a decision on them is graded (LoanApplication.grade_documents()): the
## problems at their configured rates, documents consistent with the
## application, no date of birth, problems independent of the name, look and
## finances (fair lending), every row of the grading table, and the new
## denial reason.

const Reason := LoanApplication.DenialReason
const Grade := LoanApplication.Grade
const Decision := LoanApplication.DecisionType
const DocProblem := LoanApplication.DocProblem

const SEED: int = 20261104
const TODAY: int = 20460 # an epoch day in 2026

func rng_for(stream: String, number: int, seed_value: int = SEED) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_value, stream, number])
	return rng

## Applicant `number` as LoanDeskManager builds them: finances, identity and
## documents each from their own generator.
func applicant(number: int, finance_seed: int = SEED, identity_seed: int = SEED, document_seed: int = SEED) -> LoanApplication:
	var application := LoanApplicantGenerator.generate(rng_for("finance", number, finance_seed))
	LoanApplicantGenerator.assign_identity(application, rng_for("identity", number, identity_seed), {})
	LoanApplicantGenerator.issue_documents(application, rng_for("documents", number, document_seed), TODAY)
	return application

## A sample with clean documents.
func clean(applicant_name: String) -> LoanApplication:
	for application in LoanApplicationsData.get_applications():
		if application.applicant_name == applicant_name:
			LoanApplicantGenerator.issue_documents(application, rng_for("documents", 0), TODAY, true)
			application.risk_assessment = application.calculate_risk_assessment()
			return application
	return null

## Sample `applicant_name` with documents that show `doc_problem` (and/or
## `id_problem`), found by trying document seeds (the real generator).
func with_problem(applicant_name: String, doc_problem: LoanApplication.DocProblem, id_problem: IdCard.Problem = IdCard.Problem.NONE) -> LoanApplication:
	var application := clean(applicant_name)
	for i in 5000:
		LoanApplicantGenerator.issue_documents(application, rng_for("documents", i), TODAY)
		if application.doc_problem == doc_problem and application.id_problem == id_problem:
			return application
	return null

func decide(application: LoanApplication, decision: LoanApplication.DecisionType, reasons: Array = [], verified: bool = true) -> Dictionary:
	application.decision = decision
	application.decision_amount = application.requested_amount if decision == Decision.APPROVE else 0.0
	if decision == Decision.COUNTER_OFFER:
		application.decision_amount = maxf(100.0, NpcLoanDeskWorker._decision_amount(application, decision))
	var typed: Array[LoanApplication.DenialReason] = []
	for reason: int in reasons:
		typed.append(reason as LoanApplication.DenialReason)
	return application.grade_documents(typed, verified)

# --- rates ---------------------------------------------------------------------

func test_document_problems_come_at_the_configured_rates() -> void:
	var count := 6000
	var bad_ids := 0
	var id_kinds := {}
	var doc_kinds := {}
	var unverifiable := 0
	for i in count:
		var application := applicant(i)
		if application.id_problem != IdCard.Problem.NONE:
			bad_ids += 1
			id_kinds[application.id_problem] = id_kinds.get(application.id_problem, 0) + 1
		if application.doc_problem != DocProblem.NONE:
			doc_kinds[application.doc_problem] = doc_kinds.get(application.doc_problem, 0) + 1
		if not application.documents_check_out():
			unverifiable += 1
	var doc_total := 0
	for kind: int in doc_kinds:
		doc_total += doc_kinds[kind]
	print("Loan documents over %d: bad ID %.1f%% %s; other problems %.1f%% %s; not checking out %.1f%%" % [
		count, bad_ids * 100.0 / count, id_kinds, doc_total * 100.0 / count, doc_kinds, unverifiable * 100.0 / count])
	# A bad ID at the teller window's rate (1 in 7), in its mix.
	assert_float(bad_ids / float(count)).is_between(LoanApplicantGenerator.ID_PROBLEM_CHANCE - 0.015, LoanApplicantGenerator.ID_PROBLEM_CHANCE + 0.015)
	var id_weight_total := 0
	for kind: int in KycPolicy.PROBLEM_WEIGHTS:
		id_weight_total += KycPolicy.PROBLEM_WEIGHTS[kind]
	for kind: int in KycPolicy.PROBLEM_WEIGHTS:
		var weight: int = KycPolicy.PROBLEM_WEIGHTS[kind]
		var share: float = id_kinds.get(kind, 0) / float(bad_ids)
		assert_float(share).override_failure_message("ID problem %d" % kind).is_between(weight / float(id_weight_total) - 0.05, weight / float(id_weight_total) + 0.05)
	# The other problems at DOC_PROBLEM_CHANCE, in their mix.
	assert_float(doc_total / float(count)).is_between(LoanApplicantGenerator.DOC_PROBLEM_CHANCE - 0.012, LoanApplicantGenerator.DOC_PROBLEM_CHANCE + 0.012)
	var doc_weight_total := 0
	for kind: int in LoanApplicantGenerator.DOC_PROBLEM_WEIGHTS:
		doc_weight_total += LoanApplicantGenerator.DOC_PROBLEM_WEIGHTS[kind]
	for kind: int in LoanApplicantGenerator.DOC_PROBLEM_WEIGHTS:
		var weight: int = LoanApplicantGenerator.DOC_PROBLEM_WEIGHTS[kind]
		var expected := LoanApplicantGenerator.DOC_PROBLEM_CHANCE * weight / doc_weight_total
		assert_float(doc_kinds.get(kind, 0) / float(count)).override_failure_message("document problem %d" % kind).is_between(expected - 0.008, expected + 0.008)
	# Together: 1 - (6/7)(0.9), about 23%.
	var expected_unverifiable := 1.0 - (1.0 - LoanApplicantGenerator.ID_PROBLEM_CHANCE) * (1.0 - LoanApplicantGenerator.DOC_PROBLEM_CHANCE)
	assert_float(unverifiable / float(count)).is_between(expected_unverifiable - 0.02, expected_unverifiable + 0.02)

# --- consistent documents ----------------------------------------------------------

func test_documents_match_the_application_unless_a_problem_says_otherwise() -> void:
	for i in 3000:
		var application := applicant(i)
		var label := "%s (%d, %d)" % [application.applicant_name, application.doc_problem, application.id_problem]
		var stated := roundf(application.annual_income / 12.0)
		assert_bool(application.documents_issued).is_true()
		# The ID.
		var card := application.id_card()
		assert_int(card.date_of_birth).override_failure_message(label).is_equal(0)
		match application.id_problem:
			IdCard.Problem.NONE:
				assert_bool(application.id_presented).is_true()
				assert_str(application.id_holder_name).is_equal(application.applicant_name)
				assert_int(application.id_portrait_look).is_equal(application.applicant_look)
				assert_int(application.id_expiry_date).is_greater(TODAY)
			IdCard.Problem.EXPIRED:
				assert_int(application.id_expiry_date).is_less(TODAY)
			IdCard.Problem.NAME_MISMATCH:
				assert_str(application.id_holder_name).is_not_equal(application.applicant_name)
			IdCard.Problem.WRONG_PORTRAIT:
				assert_int(KycPolicy.design_of(application.id_portrait_look)).is_not_equal(KycPolicy.design_of(application.applicant_look))
			IdCard.Problem.NO_ID:
				assert_bool(application.id_presented).is_false()
		# The pay stub and statement.
		assert_bool(application.has_pay_stub).is_equal(application.doc_problem != DocProblem.MISSING_STUB)
		assert_bool(application.has_statement).is_equal(application.doc_problem != DocProblem.MISSING_STATEMENT)
		if application.has_pay_stub:
			var net_share := application.stub_monthly_net / application.stub_monthly_gross
			assert_float(net_share).override_failure_message(label).is_between(0.715, 0.805)
			assert_bool(LoanApplicantGenerator.EMPLOYERS.has(application.stub_employer)).is_true()
			if application.doc_problem == DocProblem.OVERSTATED_INCOME:
				assert_float(application.stub_monthly_gross / stated).override_failure_message(label).is_between(0.595, 0.855)
			else:
				assert_float(application.stub_monthly_gross).override_failure_message(label).is_equal(stated)
			if application.doc_problem == DocProblem.STUB_NAME:
				assert_str(application.stub_name).is_not_equal(application.applicant_name)
				assert_str(application.stub_name.get_slice(" ", 0)).is_equal(application.applicant_name.get_slice(" ", 0))
			else:
				assert_str(application.stub_name).is_equal(application.applicant_name)
		if application.has_statement:
			assert_str(application.statement_name).is_equal(application.applicant_name)
			assert_int(application.statement_deposits.size()).is_equal(2)
			# Two payroll deposits a month, adding up to the net pay the stub shows
			# (or, with no stub, to net pay on the stated income).
			if application.has_pay_stub:
				assert_float(float(application.statement_total())).override_failure_message(label).is_equal(application.stub_monthly_net)
			else:
				assert_float(application.statement_total() / stated).override_failure_message(label).is_between(0.715, 0.805)
		assert_bool(application.documents_check_out()).is_equal(application.doc_problem == DocProblem.NONE and application.id_problem == IdCard.Problem.NONE)

## The teaching cases and other samples always come with documents that
## check out.
func test_clean_documents_have_no_problems() -> void:
	for i in 200:
		var application := clean("Maria Chen")
		LoanApplicantGenerator.issue_documents(application, rng_for("documents", i), TODAY, true)
		assert_bool(application.documents_check_out()).is_true()

# --- fair lending ----------------------------------------------------------------

## Whether an applicant's documents have a problem comes from the documents'
## own generator: the same documents seed gives the same problems whatever
## the applicant's finances, name or look.
func test_document_problems_never_depend_on_name_look_or_finances() -> void:
	for i in 500:
		var first := applicant(i)
		var other := applicant(i, SEED + 1, SEED + 2)
		assert_int(other.doc_problem).is_equal(first.doc_problem)
		assert_int(other.id_problem).is_equal(first.id_problem)

## Across 6,000 applicants, each look and each group of first names has much
## the same share of documents that don't check out, as does each tier.
func test_document_problem_rates_are_the_same_for_every_look_name_and_tier() -> void:
	var count := 6000
	var groups := {}
	var overall := 0.0
	for i in count:
		var application := applicant(i)
		var bad := 0.0 if application.documents_check_out() else 1.0
		overall += bad / count
		var first_name := application.applicant_name.get_slice(" ", 0)
		for key: String in ["look %d" % application.applicant_look, "names %d" % (LoanApplicantGenerator.FIRST_NAMES.find(first_name) % 4), "tier %d" % application.risk_tier]:
			var group: Vector2 = groups.get(key, Vector2.ZERO)
			groups[key] = group + Vector2(bad, 1.0)
	for key: String in groups:
		var group: Vector2 = groups[key]
		var share: float = group.x / group.y
		# About 500 a look: 0.08 is over 4 standard deviations.
		assert_float(absf(share - overall)).override_failure_message("%s: %.3f against %.3f" % [key, share, overall]).is_less(0.08)

# --- grading -----------------------------------------------------------------------

func test_each_row_of_the_grading_table() -> void:
	var best := LoanApplication.BEST_DECISION_SCORE
	var right := LoanApplication.REASON_RIGHT_SCORE
	var skipped := LoanApplication.VERIFY_SKIPPED_SCORE

	# Documents that don't check out, verified, rejected naming the reason:
	# caught.
	var overstated := with_problem("Maria Chen", DocProblem.OVERSTATED_INCOME)
	var caught := decide(overstated, Decision.REJECT, [Reason.UNVERIFIED])
	assert_dict(slim(caught)).is_equal({"grade": Grade.BEST, "score": best + right, "reputation": 1, "caught": true, "false_unverified": false, "skipped": false})
	# Rejected for other reasons only: reasonable, but the reason was wrong.
	var other_reason := decide(overstated, Decision.REJECT, [Reason.TOTAL_DTI])
	assert_dict(slim(other_reason)).is_equal({"grade": Grade.PARTIAL, "score": LoanApplication.PARTIAL_CREDIT_SCORE + LoanApplication.REASON_WRONG_SCORE + LoanApplication.REASON_MISSING_SCORE, "reputation": 0, "caught": false, "false_unverified": false, "skipped": false})
	# Approved or countered on them: as bad as WORST.
	for decision: int in [Decision.APPROVE, Decision.COUNTER_OFFER]:
		var result := decide(overstated, decision as LoanApplication.DecisionType)
		assert_dict(slim(result)).override_failure_message(str(decision)).is_equal({"grade": Grade.WORST, "score": LoanApplication.WORST_DECISION_SCORE, "reputation": LoanApplication.WORST_DECISION_REPUTATION, "caught": false, "false_unverified": false, "skipped": false})
	# ...and without verifying first, the procedure mistake on top.
	assert_int(decide(overstated, Decision.APPROVE, [], false)["score"]).is_equal(LoanApplication.WORST_DECISION_SCORE + skipped)

	# Every kind of problem is caught the same way.
	for problem: Array in [[DocProblem.STUB_NAME, IdCard.Problem.NONE], [DocProblem.MISSING_STUB, IdCard.Problem.NONE], [DocProblem.MISSING_STATEMENT, IdCard.Problem.NONE],
			[DocProblem.NONE, IdCard.Problem.EXPIRED], [DocProblem.NONE, IdCard.Problem.NAME_MISMATCH], [DocProblem.NONE, IdCard.Problem.WRONG_PORTRAIT], [DocProblem.NONE, IdCard.Problem.NO_ID]]:
		var doc_problem: LoanApplication.DocProblem = problem[0]
		var id_problem: IdCard.Problem = problem[1]
		var application := with_problem("Maria Chen", doc_problem, id_problem)
		assert_object(application).override_failure_message(str(problem)).is_not_null()
		assert_bool(application.documents_check_out()).is_false()
		assert_array(application.weak_points()).is_equal([Reason.UNVERIFIED])
		assert_int(application.correct_decision()).is_equal(Decision.REJECT)
		assert_bool(decide(application, Decision.REJECT, [Reason.UNVERIFIED])["caught"]).is_true()

	# Documents fine: graded as before when verified, -3 when not.
	var maria := clean("Maria Chen")
	assert_dict(slim(decide(maria, Decision.APPROVE))).is_equal({"grade": Grade.BEST, "score": best, "reputation": 1, "caught": false, "false_unverified": false, "skipped": false})
	assert_dict(slim(decide(maria, Decision.APPROVE, [], false))).is_equal({"grade": Grade.BEST, "score": best + skipped, "reputation": 1, "caught": false, "false_unverified": false, "skipped": true})
	# A good applicant turned away as "unverifiable": the decision's own grade
	# (BAD for a safe loan), the wrong reason, and the penalty.
	var refused := decide(maria, Decision.REJECT, [Reason.UNVERIFIED])
	assert_dict(slim(refused)).is_equal({
		"grade": Grade.BAD,
		"score": LoanApplication.BAD_DECISION_SCORE + LoanApplication.REASON_WRONG_SCORE + LoanApplication.FALSE_UNVERIFIED_SCORE,
		"reputation": LoanApplication.BAD_DECISION_REPUTATION + LoanApplication.FALSE_UNVERIFIED_REPUTATION,
		"caught": false, "false_unverified": true, "skipped": false,
	})
	# A risky applicant turned away for the wrong reason pays it too.
	var marcus := clean("Marcus Webb")
	var marcus_refused := decide(marcus, Decision.REJECT, [Reason.UNVERIFIED])
	assert_bool(marcus_refused["false_unverified"]).is_true()
	assert_int(marcus_refused["score"]).is_equal(best + LoanApplication.REASON_WRONG_SCORE + LoanApplication.REASON_MISSING_SCORE * 2 + LoanApplication.FALSE_UNVERIFIED_SCORE)

	# By type (staff, Approvals): documents that don't check out make Reject
	# BEST and anything else WORST, whatever the risk.
	for tier: int in LoanApplication.RiskTier.values():
		var risk := tier as LoanApplication.RiskTier
		assert_int(LoanApplication.grade(Decision.REJECT, risk, false, false)).is_equal(Grade.BEST)
		assert_int(LoanApplication.grade(Decision.APPROVE, risk, false, false)).is_equal(Grade.WORST)
		assert_int(LoanApplication.grade(Decision.COUNTER_OFFER, risk, false, false)).is_equal(Grade.WORST)
	# On the figures alone (a staff member who missed the problem).
	assert_int(overstated.correct_decision(true)).is_equal(Decision.APPROVE)

func slim(result: Dictionary) -> Dictionary:
	var copy := result.duplicate()
	copy.erase("reasons")
	return copy

func test_the_new_denial_reason() -> void:
	assert_int(Reason.values().size()).is_equal(6)
	assert_str(LoanApplication.denial_reason_label(Reason.UNVERIFIED)).is_equal("Income or identity could not be verified")
	# Only a real weak point when the documents don't check out.
	assert_bool(clean("Marcus Webb").weak_points().has(Reason.UNVERIFIED)).is_false()
	var reasons: Array[LoanApplication.DenialReason] = [Reason.UNVERIFIED]
	assert_dict(clean("Marcus Webb").grade_denial_reasons(reasons)).is_equal({"right": 0, "wrong": 1, "missing": 2, "score": LoanApplication.REASON_WRONG_SCORE + 2 * LoanApplication.REASON_MISSING_SCORE})
	var missing := with_problem("Marcus Webb", DocProblem.MISSING_STATEMENT)
	assert_dict(missing.grade_denial_reasons(reasons)).is_equal({"right": 1, "wrong": 0, "missing": 0, "score": LoanApplication.REASON_RIGHT_SCORE})
	# What was wrong, for after the fact.
	assert_str(missing.documents_problem_text()).is_equal("there was no bank statement")
	assert_str(with_problem("Maria Chen", DocProblem.NONE, IdCard.Problem.EXPIRED).documents_problem_text()).is_equal("the ID had expired")
