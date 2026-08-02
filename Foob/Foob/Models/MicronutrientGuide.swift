import Foundation

/// Reference facts for one micronutrient: the adult Daily Value the tally
/// measures against, the tolerable upper limit where one is established, what
/// the nutrient does, and what chronically overshooting it can cause.
///
/// General adult FDA Daily Values / NIH upper limits — informational, not
/// medical advice (the info sheet says so). `dailyValue` nil = no established
/// DV (the tally shows the plain amount); `upperLimit` nil = no established UL.
struct MicronutrientInfo {
    let dailyValue: Double?
    let upperLimit: Double?
    let goodFor: String
    let excess: String
}

enum MicronutrientGuide {
    /// Keyed by `MicronutrientField.label` (the stable display name).
    static let entries: [String: MicronutrientInfo] = [
        "Saturated fat": .init(
            dailyValue: 20, upperLimit: nil,
            goodFor: "A normal part of many foods and a source of energy; some is fine as part of total fat intake.",
            excess: "Consistently high intake raises LDL (\u{201C}bad\u{201D}) cholesterol, a risk factor for heart disease. The DV here is a stay-below target, not a goal to hit."
        ),
        "Trans fat": .init(
            dailyValue: nil, upperLimit: 0,
            goodFor: "No known benefit — artificial trans fats have been phased out of most food supplies.",
            excess: "Even small regular amounts raise LDL and lower HDL cholesterol; the practical target is as close to zero as possible."
        ),
        "Monounsaturated fat": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "The \u{201C}olive oil / avocado\u{201D} fat — supports healthy cholesterol levels when it replaces saturated fat.",
            excess: "No specific harm beyond its calories (9 kcal per gram adds up)."
        ),
        "Polyunsaturated fat": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "Includes omega-3 and omega-6 essential fats needed for brain and heart health.",
            excess: "No specific harm beyond its calories."
        ),
        "Fiber": .init(
            dailyValue: 28, upperLimit: nil,
            goodFor: "Digestion, steady blood sugar, cholesterol control, and feeling full.",
            excess: "Very large jumps in intake cause gas, bloating, and cramping — ramp up gradually and drink water."
        ),
        "Total sugars": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "Quick energy; naturally present in fruit and dairy alongside useful nutrients.",
            excess: "Regularly high intake drives excess calories and blood-sugar swings; most guidance focuses on limiting the added portion."
        ),
        "Added sugars": .init(
            dailyValue: 50, upperLimit: nil,
            goodFor: "Palatability and fast fuel around hard training — there's no nutritional need for added sugar.",
            excess: "Strongly linked to weight gain, tooth decay, and elevated triglycerides. The DV is a stay-below ceiling."
        ),
        "Cholesterol": .init(
            dailyValue: 300, upperLimit: nil,
            goodFor: "Your body makes what it needs for hormones and cell membranes; dietary cholesterol matters less than once thought for most people.",
            excess: "Some people are \u{201C}responders\u{201D} whose blood cholesterol tracks dietary intake — worth moderating if your LDL runs high."
        ),
        "Sodium": .init(
            dailyValue: 2300, upperLimit: 2300,
            goodFor: "Fluid balance, nerve signals, and muscle contraction — and it's lost in sweat.",
            excess: "Chronically high intake raises blood pressure in salt-sensitive people and increases cardiovascular risk."
        ),
        "Potassium": .init(
            dailyValue: 4700, upperLimit: nil,
            goodFor: "Blood-pressure regulation, muscle and nerve function; most people under-consume it.",
            excess: "From food it's very hard to overdo with healthy kidneys; supplement megadoses can disturb heart rhythm."
        ),
        "Calcium": .init(
            dailyValue: 1300, upperLimit: 2500,
            goodFor: "Bones and teeth, muscle contraction, and nerve transmission.",
            excess: "Chronic overshoot (usually from supplements) can cause kidney stones and constipation, and may interfere with iron and zinc absorption."
        ),
        "Iron": .init(
            dailyValue: 18, upperLimit: 45,
            goodFor: "Hemoglobin — carrying oxygen in your blood; low iron means fatigue and poor endurance.",
            excess: "Above the upper limit causes stomach upset and constipation; sustained overload can damage the liver. Keep iron supplements away from kids."
        ),
        "Magnesium": .init(
            dailyValue: 420, upperLimit: nil,
            goodFor: "Muscle and nerve function, sleep quality, energy production, and blood-sugar control.",
            excess: "Food sources are safe; high-dose supplements (over ~350 mg supplemental) commonly cause diarrhea."
        ),
        "Zinc": .init(
            dailyValue: 11, upperLimit: 40,
            goodFor: "Immune function, wound healing, taste, and testosterone production.",
            excess: "Chronic high doses cause nausea, suppress immunity, and create copper deficiency."
        ),
        "Phosphorus": .init(
            dailyValue: 1250, upperLimit: 4000,
            goodFor: "Bone structure and the ATP energy system.",
            excess: "Very high intakes (mostly from additives) may stress kidneys and pull calcium from bone."
        ),
        "Copper": .init(
            dailyValue: 0.9, upperLimit: 10,
            goodFor: "Iron metabolism, connective tissue, and antioxidant enzymes.",
            excess: "Overdose causes nausea and, chronically, liver damage."
        ),
        "Manganese": .init(
            dailyValue: 2.3, upperLimit: 11,
            goodFor: "Bone formation, metabolism, and antioxidant defense.",
            excess: "Chronic excess (usually occupational or supplement-driven) can affect the nervous system."
        ),
        "Selenium": .init(
            dailyValue: 55, upperLimit: 400,
            goodFor: "Thyroid hormone metabolism and antioxidant protection.",
            excess: "Selenosis: brittle hair and nails, garlic breath, and nerve issues. A couple of Brazil nuts a day already covers you."
        ),
        "Iodine": .init(
            dailyValue: 150, upperLimit: 1100,
            goodFor: "Making thyroid hormone — which sets your metabolic rate.",
            excess: "Both too little and too much disturb the thyroid; kelp supplements are the usual culprit for excess."
        ),
        "Chromium": .init(
            dailyValue: 35, upperLimit: nil,
            goodFor: "Assists insulin in moving glucose into cells.",
            excess: "No established toxic level from food; very high supplement doses have occasionally been linked to kidney stress."
        ),
        "Molybdenum": .init(
            dailyValue: 45, upperLimit: 2000,
            goodFor: "A cofactor for enzymes that break down toxins and sulfur amino acids.",
            excess: "Extremely rare; very high intakes may raise uric acid (gout-like symptoms)."
        ),
        "Chloride": .init(
            dailyValue: 2300, upperLimit: 3600,
            goodFor: "Stomach acid production and fluid balance — sodium's partner in salt.",
            excess: "Tracks salt intake; excess contributes to the same blood-pressure concerns as sodium."
        ),
        "Vitamin A": .init(
            dailyValue: 900, upperLimit: 3000,
            goodFor: "Vision (especially night vision), immune function, and skin health.",
            excess: "Preformed vitamin A accumulates: chronic excess causes headaches, liver damage, bone loss, and birth defects in pregnancy. Beta-carotene from vegetables doesn't carry this risk."
        ),
        "Vitamin C": .init(
            dailyValue: 90, upperLimit: 2000,
            goodFor: "Immune support, collagen production, and iron absorption; an antioxidant.",
            excess: "Above ~2 g/day: diarrhea and stomach cramps, and higher kidney-stone risk in prone people. Extra is excreted, not stored."
        ),
        "Vitamin D": .init(
            dailyValue: 20, upperLimit: 100,
            goodFor: "Calcium absorption, bone strength, immune and mood regulation. Hard to get from food alone.",
            excess: "Supplement overdose raises blood calcium: nausea, weakness, kidney stones, and heart rhythm problems. Sun exposure can't overdose you."
        ),
        "Vitamin E": .init(
            dailyValue: 15, upperLimit: 1000,
            goodFor: "Protects cell membranes from oxidation; supports immune function.",
            excess: "High-dose supplements thin the blood — a bleeding risk, especially alongside blood thinners."
        ),
        "Vitamin K": .init(
            dailyValue: 120, upperLimit: nil,
            goodFor: "Blood clotting and bone metabolism.",
            excess: "No known toxicity from food — but it directly counteracts warfarin, so consistency matters on that medication."
        ),
        "Thiamin (B1)": .init(
            dailyValue: 1.2, upperLimit: nil,
            goodFor: "Turning carbs into energy; nerve function.",
            excess: "No known toxicity — excess is excreted in urine."
        ),
        "Riboflavin (B2)": .init(
            dailyValue: 1.3, upperLimit: nil,
            goodFor: "Energy production and metabolizing fats and drugs.",
            excess: "No known toxicity; high doses just turn urine bright yellow (harmless)."
        ),
        "Niacin (B3)": .init(
            dailyValue: 16, upperLimit: 35,
            goodFor: "Energy metabolism, DNA repair, and healthy skin.",
            excess: "Supplemental doses above ~35 mg cause the \u{201C}niacin flush\u{201D}; gram-level doses can injure the liver."
        ),
        "Vitamin B6": .init(
            dailyValue: 1.7, upperLimit: 100,
            goodFor: "Protein metabolism, neurotransmitters, and immune function.",
            excess: "Chronic high-dose supplements cause nerve damage (numbness, tingling) that can be lasting."
        ),
        "Folate": .init(
            dailyValue: 400, upperLimit: 1000,
            goodFor: "DNA synthesis and red blood cells; critical before and during early pregnancy.",
            excess: "High folic-acid intake can mask a B12 deficiency, letting its nerve damage progress silently."
        ),
        "Vitamin B12": .init(
            dailyValue: 2.4, upperLimit: nil,
            goodFor: "Nerve function, red blood cells, and DNA synthesis; only naturally present in animal foods.",
            excess: "No established toxicity — absorption is self-limiting."
        ),
        "Biotin (B7)": .init(
            dailyValue: 30, upperLimit: nil,
            goodFor: "Metabolizing fats, carbs, and protein; associated with hair, skin, and nail health.",
            excess: "Megadoses (common in hair/skin gummies and energy drinks) can trigger acne breakouts in some people and — importantly — distort lab tests, including thyroid and cardiac panels. Tell your doctor if you take high-dose biotin."
        ),
        "Pantothenic acid (B5)": .init(
            dailyValue: 5, upperLimit: nil,
            goodFor: "Making coenzyme A — central to producing energy from food; in nearly everything you eat.",
            excess: "Essentially non-toxic; very large doses can cause diarrhea."
        ),
        "Choline": .init(
            dailyValue: 550, upperLimit: 3500,
            goodFor: "Liver fat processing, cell membranes, and the neurotransmitter acetylcholine (memory, muscle control).",
            excess: "Gram-level excess causes a fishy body odor, sweating, and low blood pressure."
        ),
        "Caffeine": .init(
            dailyValue: nil, upperLimit: 400,
            goodFor: "Alertness, focus, and a measurable boost to endurance and strength performance.",
            excess: "Past ~400 mg/day (less for some people): jitters, anxiety, elevated heart rate, and — the stealthy one — degraded sleep that undermines recovery. Late-day doses linger; half-life is ~5 hours."
        ),
        "Creatine": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "One of the best-studied supplements: increases strength, power output, and lean mass; 3\u{2013}5 g daily is the standard dose.",
            excess: "Above ~10 g in one sitting commonly causes stomach upset; otherwise well tolerated in healthy people. It raises creatinine on blood tests without indicating kidney harm — mention it to your doctor. Drink enough water."
        ),
        "L-Citrulline": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "Raises blood arginine and nitric oxide — better blood flow, \u{201C}pumps\u{201D}, and modest endurance benefits. Typical pre-workout dose is 6\u{2013}8 g (or 8 g citrulline malate).",
            excess: "Well tolerated even at high doses; very large amounts can cause stomach upset. It lowers blood pressure slightly — relevant alongside blood-pressure medication."
        ),
        "Beta-alanine": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "Builds muscle carnosine, buffering acid during hard 1\u{2013}4 minute efforts. The effective dose is 3.2\u{2013}6.4 g per day, taken consistently — timing doesn't matter.",
            excess: "The face-and-hands tingling (paresthesia) from a full dose is harmless and fades within an hour; split doses avoid it. No other established risks at studied doses."
        ),
        "Betaine": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "Trimethylglycine, from beets: supports power output and cellular hydration in some studies; 2.5 g daily is the researched dose.",
            excess: "High doses can cause a fishy body odor and raise blood cholesterol modestly in some people; GI upset past several grams."
        ),
        "Taurine": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "An amino acid abundant in muscle and heart tissue — the energy-drink staple. Evidence suggests mild endurance and antioxidant benefits; ~0.5\u{2013}3 g doses are typical.",
            excess: "Very safe at studied doses (up to ~3 g/day long-term, more short-term). The caffeine riding alongside it in energy drinks is the ingredient to actually watch."
        ),
        "L-Tyrosine": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "Precursor to dopamine and adrenaline; helps maintain focus under stress, sleep deprivation, and long training sessions. Typical doses are 500\u{2013}2000 mg.",
            excess: "Well tolerated; occasional headaches or nausea at gram-level doses. Avoid with MAOI antidepressants and check with a doctor if you have thyroid conditions (it's also a thyroid-hormone precursor)."
        ),
        "L-Theanine": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "The calm-focus amino acid from tea. Pairs with caffeine to smooth jitters while keeping alertness; 100\u{2013}400 mg is typical (a 1:1 to 2:1 theanine:caffeine ratio is common).",
            excess: "One of the safest supplements known; very high doses may cause drowsiness or headache. It can mildly lower blood pressure."
        ),
        "Alpha-GPC": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "A highly bioavailable choline source that crosses into the brain — used for focus and a possible power-output bump. Pre-workouts use 300\u{2013}600 mg. (Tracked separately from the Choline field, which is elemental choline from food.)",
            excess: "Occasional headaches, dizziness, or heartburn. One large observational study associated multi-year daily use with higher stroke risk — a reason to treat it as a sometimes tool, not a daily staple."
        ),
        "L-Norvaline": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "Marketed as an arginase inhibitor to extend nitric-oxide \u{201C}pumps\u{201D}. Honest read: human evidence is thin — it rides along in pre-workouts at 100\u{2013}200 mg mostly on theory.",
            excess: "Cell studies have flagged potential neurotoxicity at high concentrations. Nothing is established in humans at label doses, but of everything in a pre-workout, this is the ingredient with the least reason to chase more of."
        ),
        "Huperzine A": .init(
            dailyValue: nil, upperLimit: nil,
            goodFor: "A plant alkaloid that slows the breakdown of acetylcholine — sharper focus and mind-muscle connection. Effective at tiny doses: 50\u{2013}200 mcg. Labels often print the herb (\u{201C}Huperzia serrata 5 mg, 1% huperzine A\u{201D} = 50 mcg of the active).",
            excess: "It has a long half-life (~12 h) and accumulates with daily use — nausea, cramps, vivid dreams, and a racing heart are the overshoot signs. Common practice is cycling (e.g. a few days off each week) rather than daily use; avoid with cholinergic medications."
        ),
    ]

    static func info(for label: String) -> MicronutrientInfo? { entries[label] }
}
