module Pdf
  # Phase 18.1: Wheel of Life PDF renderer. The form Cerca uses is
  # the Coaches Training Institute Assessment Wheel — 9 life areas,
  # each with 4-5 statements scored 1-10. We render:
  #   - meta (date, completed-by, submitted)
  #   - the radial chart of percentages, drawn as a 9-spoke spider
  #     polygon in Prawn primitives (no library dependency)
  #   - per-area summary table (raw / max / %)
  #   - per-area item responses
  #   - reflection answers
  #   - attribution footer (per Phase 18 Q4: PDF only, not client UI)
  class WheelOfLifeRenderer < CercaDocument
    # The 9 area labels in the order they appear on the source form.
    # Keys match WheelOfLifeAssessment::AREAS (snake_case).
    AREA_LABELS = {
      "career"               => "Career",
      "fun_and_recreation"   => "Fun and Recreation",
      "money_and_finances"   => "Money and Finances",
      "physical_environment" => "Physical Environment",
      "personal_growth"      => "Personal Growth",
      "health_and_wellbeing" => "Health and Wellbeing",
      "friends"              => "Friends",
      "family"               => "Family",
      "significant_other"    => "Significant Other"
    }.freeze

    # Item wording transcribed from the canonical Cerca form for the
    # PDF. The FE keeps an identical source in src/lib/wheelOfLifeItems.ts —
    # update both if Cerca revises the wording.
    ITEMS = {
      "career" => [
        "I love my work.",
        "I feel my talents and skills are well used in my work.",
        "I enjoy my work environment and the people with whom I work.",
        "I see opportunity for growth and development in my position.",
        "I feel like I have found my right livelihood."
      ],
      "fun_and_recreation" => [
        "I regularly take the time I need to experience play, adventure and leisure.",
        "I know what activities renew me and bring me alive and I participate in them regularly.",
        "I create plenty of space in my life to relax and enjoy myself and others.",
        "I create fun for myself and others."
      ],
      "money_and_finances" => [
        "I have enough money to do the things I want to do and to accomplish the things that are important to me.",
        "I manage my money and financial affairs and records well.",
        "I am free from worry and anxiety about money.",
        "My financial future feels robust and sustainable."
      ],
      "physical_environment" => [
        "I feel nourished and supported by my home.",
        "I am surrounded by things that I love and have meaning to me.",
        "The level of order in my surroundings is appropriate to my needs. (it serves me)",
        "My wardrobe is a clear expression of who I am. I love being in the clothes I wear."
      ],
      "personal_growth" => [
        "I have a belief system that sustains me no matter what circumstances life throws at me.",
        "I am engaged in the unfolding story of my life and approach each day as an adventure.",
        "I regularly experience living a life that I love and loving who I am becoming.",
        "I regularly engage in activities and learning that grow and expand me."
      ],
      "health_and_wellbeing" => [
        "I approach my health in a proactive and generative way, rather than crisis management mode.",
        "I am satisfied with my level of vitality and well being.",
        "I have support systems and structures in place that allow me to easily maintain my health and well being.",
        "I am conscious of my body and fitness level and take responsibility for my physical well-being.",
        "I know what works for me to maintain my health and I consistently do it."
      ],
      "friends" => [
        "I have a sufficient number of great friends.",
        "My friendships nourish and sustain me.",
        "I am a good friend and I make myself available to my friendships.",
        "I trust the relationships I have with my friends.",
        "I love and make the most of the time I spend with my friends."
      ],
      "family" => [
        "I am satisfied with the level of contact I have with my family.",
        "Nothing feels hidden or witheld in my relationships with family members.",
        "I am satisfied with the role I play and the level of contribution I have in my family.",
        "I have created the experience of family in my life, whether or not it is with my biological relatives."
      ],
      "significant_other" => [
        "I am open to creating an intimate loving relationship.",
        "I am free from past resentments or blame in the area of intimate relationships.",
        "I am willing to risk myself for the sake of intimacy.",
        "I create romance in my life."
      ]
    }.freeze

    def render_body(pdf)
      render_meta(pdf)
      render_chart(pdf)
      render_summary_table(pdf)
      render_area_responses(pdf)
      render_reflections(pdf)
      render_signature(pdf)
      render_attribution(pdf)
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

    # Draws a 9-spoke spider chart at the current cursor position.
    # The chart uses Prawn primitives (stroke_polygon, stroke_line,
    # text_box) so we don't take a library dependency.
    def render_chart(pdf)
      section(pdf, "Wheel of Life") do
        chart_size = 280  # box side in pts
        cx_in_bounds = pdf.bounds.width / 2.0
        # Reserve vertical space + a margin for the axis labels.
        pdf.move_down 10
        chart_top_y = pdf.cursor
        radius = (chart_size / 2.0) - 30  # leave margin for labels

        # Compute the center in absolute page coordinates. Prawn's
        # bounding-box origin is the lower-left of the content area,
        # but stroke methods accept coords relative to bounds.
        center_x = cx_in_bounds
        center_y = chart_top_y - chart_size / 2.0

        # Concentric reference circles for 10/20/.../100%.
        pdf.stroke_color "CBD5E1"  # slate-300
        pdf.line_width 0.4
        (1..10).each do |step|
          r = radius * (step / 10.0)
          pdf.stroke_circle [center_x, center_y], r
        end

        # 9 spokes + axis labels.
        pdf.line_width 0.5
        AREA_LABELS.keys.each_with_index do |area, i|
          angle = spoke_angle(i)
          x = center_x + radius * Math.cos(angle)
          y = center_y + radius * Math.sin(angle)
          pdf.stroke_line [center_x, center_y], [x, y]

          # Label sits slightly outside the spoke endpoint.
          label_r = radius + 14
          lx = center_x + label_r * Math.cos(angle)
          ly = center_y + label_r * Math.sin(angle)
          label = AREA_LABELS[area]
          pdf.fill_color BRAND_GREY
          pdf.font_size 7
          # Use text_box centered on (lx, ly). Prawn text_box origin
          # is the top-left of the box, so we offset.
          pdf.text_box label,
            at: [lx - 35, ly + 5],
            width: 70,
            height: 14,
            align: :center,
            overflow: :shrink_to_fit,
            disable_wrap_by_char: true
        end

        # Plot the polygon for the client's percentages.
        totals = record.totals || {}
        points = AREA_LABELS.keys.each_with_index.map do |area, i|
          pct = (totals.dig(area, "percentage") || 0).to_f
          r = radius * (pct / 100.0)
          angle = spoke_angle(i)
          [center_x + r * Math.cos(angle), center_y + r * Math.sin(angle)]
        end

        # Fill (lightly) + stroke the polygon.
        pdf.fill_color BRAND_DARK
        pdf.transparent(0.2) do
          pdf.fill_polygon(*points)
        end
        pdf.stroke_color BRAND_DARK
        pdf.line_width 1.0
        pdf.stroke_polygon(*points)

        # Dots at each vertex.
        pdf.fill_color BRAND_DARK
        points.each do |x, y|
          pdf.fill_circle [x, y], 2.0
        end

        # Reset stroke + cursor below the chart area.
        pdf.line_width 1
        pdf.stroke_color "000000"
        pdf.fill_color BODY_GREY
        pdf.move_cursor_to(chart_top_y - chart_size - 10)
      end
    end

    # Spokes start at top (90°) and proceed clockwise — matching how
    # the source form lays out the wheel.
    def spoke_angle(index)
      # index 0 → 90° (top), going clockwise.
      Math::PI / 2 - (2 * Math::PI * index / 9.0)
    end

    def render_summary_table(pdf)
      section(pdf, "Summary") do
        totals = record.totals || {}
        AREA_LABELS.each do |area, label|
          t = totals[area] || {}
          total = t["total"] || 0
          max = t["max"] || (WheelOfLifeAssessment::AREAS[area] * 10)
          pct = t["percentage"] || 0
          pdf.formatted_text [
            { text: "#{label}: ", styles: [:bold], color: BRAND_GREY },
            { text: "#{total} / #{max}  ", color: BODY_GREY },
            { text: "(#{pct}%)", styles: [:bold], color: BRAND_DARK }
          ]
          pdf.move_down 3
        end
      end
    end

    def render_area_responses(pdf)
      section(pdf, "Item responses") do
        pdf.fill_color BRAND_GREY
        pdf.font_size 9
        pdf.text "Scale: 1 (Highly Disagree) to 10 (Highly Agree).",
          style: :italic
        pdf.fill_color BODY_GREY
        pdf.move_down 6

        AREA_LABELS.each do |area, label|
          pdf.move_down 6
          pdf.fill_color BRAND_DARK
          pdf.font_size 10
          pdf.text label, style: :bold
          pdf.fill_color BODY_GREY
          pdf.move_down 2

          items = ITEMS[area] || []
          responses = (record.scores || {})[area] || []
          items.each_with_index do |text, i|
            response = responses[i]
            response_text = response.nil? ? "—" : response.to_s
            pdf.font_size 9
            pdf.formatted_text [
              { text: "#{i + 1}. ", styles: [:bold], color: BRAND_GREY },
              { text: "#{text}  ", color: BODY_GREY },
              { text: "[#{response_text}]", styles: [:bold], color: BRAND_DARK }
            ]
            pdf.move_down 2
          end
        end
      end
    end

    def render_reflections(pdf)
      section(pdf, "Reflection") do
        narrative(pdf,
          "What area on the wheel are you most wanting and willing to make a difference with?",
          record.focus_area)
        narrative(pdf,
          "What is the current state of this area in your life?",
          record.current_state)
        narrative(pdf,
          "What is missing or not working for you in this area?",
          record.whats_missing)
        narrative(pdf,
          "What would you like to create in this area?",
          record.what_to_create)
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

    # Per Phase 18 Q4: attribution to the originating instrument
    # appears on the PDF (but not on the client's locked confirmation
    # view in the FE).
    def render_attribution(pdf)
      pdf.move_down 16
      pdf.fill_color BRAND_GREY
      pdf.font_size 8
      pdf.text "The Assessment Wheel was developed by the Coaches Training Institute.",
        align: :center, style: :italic
      pdf.fill_color BODY_GREY
    end
  end
end
