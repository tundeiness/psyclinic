module Pdf
  # Renders a DASS-42 assessment as a Cerca-branded PDF. The therapist
  # uses this for the clinical record. Includes the published Lovibond
  # & Lovibond DASS-42 item content (paraphrased clinically), the
  # client's responses, subscale totals, and severity bands.
  #
  # NOTE on item wording: the DASS-42 is published by the Psychology
  # Foundation of Australia. Per the Phase 17 brief, Cerca is shipping
  # now; if/when permission is formalized we'll revisit any wording
  # changes. The strings here are the canonical clinical wording.
  class DassRenderer < CercaDocument
    # 42 canonical DASS-42 items (Lovibond & Lovibond, 1995),
    # transcribed from the canonical DASS-42 form Cerca provided.
    # Keep in sync with src/lib/dassItems.ts on the frontend.
    ITEMS = {
      1  => "I found myself getting upset by quite trivial things",
      2  => "I was aware of dryness of my mouth",
      3  => "I couldn't seem to experience any positive feeling at all",
      4  => "I experienced breathing difficulty (eg, excessively rapid breathing, breathlessness in the absence of physical exertion)",
      5  => "I just couldn't seem to get going",
      6  => "I tended to over-react to situations",
      7  => "I had a feeling of shakiness (eg, legs going to give way)",
      8  => "I found it difficult to relax",
      9  => "I found myself in situations that made me so anxious I was most relieved when they ended",
      10 => "I felt that I had nothing to look forward to",
      11 => "I found myself getting upset rather easily",
      12 => "I felt that I was using a lot of nervous energy",
      13 => "I felt sad and depressed",
      14 => "I found myself getting impatient when I was delayed in any way (eg, elevators, traffic lights, being kept waiting)",
      15 => "I had a feeling of faintness",
      16 => "I felt that I had lost interest in just about everything",
      17 => "I felt I wasn't worth much as a person",
      18 => "I felt that I was rather touchy",
      19 => "I perspired noticeably (eg, hands sweaty) in the absence of high temperatures or physical exertion",
      20 => "I felt scared without any good reason",
      21 => "I felt that life wasn't worthwhile",
      22 => "I found it hard to wind down",
      23 => "I had difficulty in swallowing",
      24 => "I couldn't seem to get any enjoyment out of the things I did",
      25 => "I was aware of the action of my heart in the absence of physical exertion (eg, sense of heart rate increase, heart missing a beat)",
      26 => "I felt down-hearted and blue",
      27 => "I found that I was very irritable",
      28 => "I felt I was close to panic",
      29 => "I found it hard to calm down after something upset me",
      30 => "I feared that I would be \"thrown\" by some trivial but unfamiliar task",
      31 => "I was unable to become enthusiastic about anything",
      32 => "I found it difficult to tolerate interruptions to what I was doing",
      33 => "I was in a state of nervous tension",
      34 => "I felt I was pretty worthless",
      35 => "I was intolerant of anything that kept me from getting on with what I was doing",
      36 => "I felt terrified",
      37 => "I could see nothing in the future to be hopeful about",
      38 => "I felt that life was meaningless",
      39 => "I found myself getting agitated",
      40 => "I was worried about situations in which I might panic and make a fool of myself",
      41 => "I experienced trembling (eg, in the hands)",
      42 => "I found it difficult to work up the initiative to do things"
    }.freeze

    LIKERT_LABELS = {
      0 => "Did not apply",
      1 => "Some / sometimes",
      2 => "Considerable / often",
      3 => "Very much / most of the time"
    }.freeze

    SEVERITY_LABEL = {
      "normal" => "Normal",
      "mild" => "Mild",
      "moderate" => "Moderate",
      "severe" => "Severe",
      "extremely_severe" => "Extremely severe"
    }.freeze

    SEVERITY_COLOR = {
      "normal" => "059669",            # emerald-600
      "mild" => "CA8A04",              # amber-600
      "moderate" => "EA580C",          # orange-600
      "severe" => "DC2626",            # red-600
      "extremely_severe" => "991B1B"   # red-800
    }.freeze

    def render_body(pdf)
      render_meta(pdf)
      render_scores(pdf)
      render_responses(pdf)
      render_signature(pdf)
    end

    private

    def render_meta(pdf)
      section(pdf, "Assessment details") do
        field(pdf, "Assessment date", record.assessment_date)
        field(pdf, "Completed by",
          record.author&.full_name || "Client")
        field(pdf, "Submitted",
          record.signed_at&.strftime("%-d %b %Y at %H:%M") || "(draft)")
      end
    end

    def render_scores(pdf)
      section(pdf, "Subscale scores & severity") do
        render_subscale_line(pdf, "Depression",
          record.depression_score, record.depression_severity)
        render_subscale_line(pdf, "Anxiety",
          record.anxiety_score, record.anxiety_severity)
        render_subscale_line(pdf, "Stress",
          record.stress_score, record.stress_severity)
      end
    end

    def render_subscale_line(pdf, label, score, severity)
      severity_color = SEVERITY_COLOR[severity] || BODY_GREY
      severity_text = SEVERITY_LABEL[severity] || "—"
      pdf.font_size 10
      pdf.formatted_text [
        { text: "#{label}: ", styles: [:bold], color: BRAND_GREY },
        { text: "#{score || 0}  ", color: BODY_GREY },
        { text: "(#{severity_text})", styles: [:bold], color: severity_color }
      ]
      pdf.move_down 4
    end

    def render_responses(pdf)
      section(pdf, "Item responses") do
        pdf.fill_color BRAND_GREY
        pdf.font_size 9
        pdf.text "Response scale: 0 = Did not apply, 1 = Some/sometimes, " \
                 "2 = Considerable/often, 3 = Very much/most of the time.",
          style: :italic
        pdf.fill_color BODY_GREY
        pdf.move_down 4

        (1..42).each do |n|
          response = record.item(n)
          text = ITEMS[n] || "(item #{n})"
          response_text = response.nil? ? "—" : "#{response}"
          pdf.font_size 9
          pdf.formatted_text [
            { text: "#{n}. ", styles: [:bold], color: BRAND_GREY },
            { text: "#{text}  ", color: BODY_GREY },
            { text: "[#{response_text}]", styles: [:bold], color: BRAND_DARK }
          ]
          pdf.move_down 2
        end
      end
    end

    def render_signature(pdf)
      section(pdf, "Signature") do
        if record.signed?
          field(pdf, "Submitted by", record.signed_by&.full_name)
          field(pdf, "Submitted at",
            record.signed_at&.strftime("%-d %b %Y at %H:%M"))
        else
          pdf.fill_color "B45309"
          pdf.text "This assessment is a DRAFT and has not yet been submitted.",
            style: :bold
          pdf.fill_color BODY_GREY
        end
      end
    end
  end
end
