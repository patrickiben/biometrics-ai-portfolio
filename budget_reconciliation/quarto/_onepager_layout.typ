#set par(leading: 0.5em)
#show heading: set text(fill: rgb("#5b8cff"), size: 11pt)
#show heading: set block(above: 0.7em, below: 0.45em)

#align(center)[
  #text(size: 16pt, weight: "bold", fill: rgb("#e9edf7"))[Find Hours \u{2014} budget reconciliation, effort only]
  #v(-5pt)
  #text(size: 8pt, fill: rgb("#94a1c0"))[Hours / effort only. No dollars, rates, or headcount. Synthetic data.]
]

#v(3pt)
#rect(width: 100%, fill: rgb("#1b1f28"), stroke: rgb("#3a4157"), inset: 9pt, radius: 6pt)[
  #text(fill: rgb("#43c47d"), weight: "bold", size: 11pt)[The formula] #h(8pt)
  #text(size: 12pt)[*Net findable* = ( #sym.sum Planned + Contingency ) #sym.minus #sym.sum EAC]
  #linebreak()
  #text(fill: rgb("#94a1c0"))[= ( #planned + #cont ) #sym.minus #eac = ] #text(fill: rgb("#43c47d"), weight: "bold")[#findable h]
]

#v(5pt)
#grid(columns: (1fr, 1fr), gutter: 14pt,
[
  == When a new ask lands \u{2014} 4 steps
  #set enum(numbering: "1.", spacing: 0.55em)
  + *Reallocate under-run slack* from tasks tracking under plan (planned #sym.minus EAC, floored at 0).
  + *Draw contingency* (management reserve) for whatever slack does not cover; log what it funded.
  + *Defer / re-sequence* lower-priority scope to free planned hours this period.
  + *Change order* for the residual: lead biostat + PM review, sponsor sign-off, SOW amended.
],
[
  == Where the numbers come from
  #table(columns: (auto, 1fr), stroke: rgb("#3a4157"), inset: 5pt,
    fill: (_, row) => if row == 0 { rgb("#2a2f3a") } else { none },
    text(fill: rgb("#e9edf7"), weight: "bold")[Column], text(fill: rgb("#e9edf7"), weight: "bold")[Source of record],
    [Planned], [SOW / budget grid in CTMS],
    [Actual to date], [Timesheet system],
    [% complete, EAC], [Your estimate + progress tracker],
    [Change order], [Contract: PM review + sponsor sign-off],
  )
]
)

#v(6pt)
== Absorbable vs change order
#grid(columns: (1fr, 1fr), gutter: 12pt,
  rect(width: 100%, fill: rgb("#1e3a28"), stroke: rgb("#43c47d"), inset: 9pt, radius: 6pt)[
    #text(weight: "bold", size: 11pt)[Ask 45 h #sym.arrow.r #f45verdict]
    #linebreak()
    #text(size: 9pt)[#f45slack h from under-run slack + #f45cont h from contingency, 0 residual. Reserve left: #f45left h.]
  ],
  rect(width: 100%, fill: rgb("#3a1e24"), stroke: rgb("#e8657a"), inset: 9pt, radius: 6pt)[
    #text(weight: "bold", size: 11pt)[Ask 90 h #sym.arrow.r #f90verdict]
    #linebreak()
    #text(size: 9pt)[#netslack h slack + #cont h contingency exhausted, ] #text(weight: "bold", fill: rgb("#e8657a"))[#f90short h] #text(size: 9pt)[ residual = new scope. Goes to the change-order process.]
  ]
)

#v(6pt)
#grid(columns: (1fr, 1fr), gutter: 14pt,
[
  == Where it runs \u{2014} the systems
  #set list(spacing: 0.5em)
  - *SOW / budget grid (CTMS)* feeds planned hours into the ledger.
  - *Timesheet system* feeds actual-to-date.
  - *Your estimate + progress tracker* set % complete and EAC.
  - *The tool* rolls these up; it connects to none of them. You transcribe current figures in, so the reconciliation is attributable and stands on its own.
  - *Contract process* (lead biostat + PM review, sponsor sign-off, SOW amended) handles any residual.
],
[
  == Read the ledger \u{2014} worked
  #set list(spacing: 0.5em)
  - Per task, *under-run slack* = max(0, planned #sym.minus EAC). A task forecast under plan gives up slack; a task over-running (EAC > planned) is *watched, not raided*.
  - Sum the per-task slack to get *net slack* (#netslack h here), then add *contingency* (#cont h) for *net findable* = #findable h.
  - Source a new ask in order: slack first, then contingency, then the residual is a change order.
]
)

#v(6pt)
== Thresholds \u{2014} how far an ask can go before a change order
#table(columns: (auto, auto, 1fr), stroke: rgb("#3a4157"), inset: 5pt,
  fill: (_, row) => if row == 0 { rgb("#2a2f3a") } else { none },
  text(fill: rgb("#e9edf7"), weight: "bold")[Ask size], text(fill: rgb("#e9edf7"), weight: "bold")[Sourced from], text(fill: rgb("#e9edf7"), weight: "bold")[Verdict],
  [Up to #netslack h], [Under-run slack only], [Absorbable, reserve untouched],
  [#netslack h to #findable h], [Slack + contingency], [Absorbable, reserve drawn (log it)],
  [Above #findable h], [Exceeds net headroom], [Residual is a change order],
)

#v(8pt)
#rect(width: 100%, fill: rgb("#1b1f28"), stroke: rgb("#3a4157"), inset: 9pt, radius: 6pt)[
  #text(fill: rgb("#5b8cff"), weight: "bold")[Run it] #h(8pt)
  #text(font: "Menlo", size: 9pt)[shiny::runApp("budget_reconciliation/shiny")]
  #h(10pt) #text(size: 8pt, fill: rgb("#94a1c0"))[The KPIs and verdict recompute live as you edit an EAC or change the ask. Hours / effort only; pricing is handled downstream by the PM.]
]
