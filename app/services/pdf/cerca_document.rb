require "prawn"

module Pdf
  # Phase 15: shared PDF base class for Cerca Africa clinical
  # documents. Handles the consistent visual identity (centered logo
  # header with double rule, watermark for unsigned/draft records,
  # confidential footer with generated-by attribution + page number)
  # so the per-document renderers only need to handle the body.
  #
  # Usage:
  #   class IntakeFormRenderer < Pdf::CercaDocument
  #     def render_body(pdf)
  #       section(pdf, "Personal information") do
  #         field(pdf, "Full name", record.client_profile.full_name)
  #         ...
  #       end
  #     end
  #   end
  #
  #   Pdf::IntakeFormRenderer.new(
  #     record: intake_form,
  #     generated_by: current_user,
  #     title: "Intake form"
  #   ).render  # → binary PDF string
  class CercaDocument
    # Cerca Africa visual constants. Kept here so all clinical PDFs
    # render with the same identity.
    CLINIC_NAME    = "Cerca Africa Mind & Behaviour Clinic".freeze
    CLINIC_TAGLINE = "Clinical psychology · Lagos, Nigeria".freeze

    BRAND_DARK  = "0F4D43".freeze  # The deep emerald used in the FE brand palette.
    BRAND_GREY  = "475569".freeze  # slate-600 — body text accent.
    BODY_GREY   = "1F2937".freeze  # slate-800 — primary body text.
    MUTED_GREY  = "94A3B8".freeze  # slate-400 — footer / watermark text.

    def initialize(record:, generated_by:, title:)
      @record = record
      @generated_by = generated_by
      @title = title
    end

    attr_reader :record, :generated_by, :title

    # Binary PDF as a string. Caller passes it through send_data with
    # the right Content-Type / Content-Disposition.
    def render
      pdf = Prawn::Document.new(
        page_size: "A4",
        margin: [60, 50, 60, 50],  # top, right, bottom, left (in pts)
        info: {
          Title: "#{title} — #{record.client_profile.full_name}",
          Author: CLINIC_NAME,
          Creator: CLINIC_NAME,
          CreationDate: Time.current
        }
      )

      # The watermark goes on every page, including ones added by
      # text-flowing helpers. Prawn's repeat(:all) re-renders the
      # block on every page. We call repeat BEFORE rendering the
      # body so it sits underneath the content.
      apply_watermark(pdf) if draft?

      render_header(pdf)
      render_title(pdf)
      render_body(pdf)
      render_footer_on_all_pages(pdf)

      pdf.render
    end

    protected

    # Subclasses MUST override this to render their specific body.
    def render_body(_pdf)
      raise NotImplementedError, "#{self.class} must implement #render_body(pdf)"
    end

    # ── Shared section helpers used by subclasses ────────────────

    # Renders a section header (capitalized, brand-dark, separator
    # line underneath) followed by whatever the block produces. Adds
    # vertical breathing room before and after.
    def section(pdf, heading)
      pdf.move_down 14
      pdf.fill_color BRAND_DARK
      pdf.font_size 11
      pdf.text heading.upcase, character_spacing: 1.2
      pdf.stroke_color "CBD5E1"  # slate-300
      pdf.stroke_horizontal_rule
      pdf.move_down 8
      pdf.fill_color BODY_GREY
      pdf.font_size 10
      yield if block_given?
    end

    # Inline label + value pair. Used for short factual fields
    # ("Date of birth: 1990-01-15"). Blank values render an em-dash
    # so the document is uniformly populated rather than visually
    # patchy.
    def field(pdf, label, value)
      pdf.font_size 10
      shown = value.to_s.strip.presence || "—"
      pdf.formatted_text [
        { text: "#{label}: ", styles: [:bold], color: BRAND_GREY },
        { text: shown, color: BODY_GREY }
      ]
      pdf.move_down 4
    end

    # Multi-line narrative ("Presenting complaint", "Therapy goals").
    # Renders the label on its own line then the text in a regular
    # paragraph. Blank values render an em-dash like fields.
    def narrative(pdf, label, text)
      pdf.move_down 6
      pdf.fill_color BRAND_GREY
      pdf.font_size 10
      pdf.text label, style: :bold
      pdf.fill_color BODY_GREY
      pdf.move_down 2
      body = text.to_s.strip.presence || "—"
      pdf.text body, leading: 2
    end

    # Convenience for boolean fields. Renders "Yes" / "No" / "—" so
    # the reader can tell the difference between "answered no" and
    # "not yet asked" (which the underlying schema treats as nil).
    def bool_field(pdf, label, value)
      shown = value.nil? ? "—" : (value ? "Yes" : "No")
      pdf.formatted_text [
        { text: "#{label}: ", styles: [:bold], color: BRAND_GREY },
        { text: shown, color: BODY_GREY }
      ]
      pdf.move_down 4
    end

    # ── Internal ─────────────────────────────────────────────────

    def draft?
      record.respond_to?(:signed?) && !record.signed?
    end

    def render_header(pdf)
      # Centered logo. If the file is missing for any reason, skip
      # silently — we'd rather generate a slightly-less-branded PDF
      # than 500 the request.
      logo_path = Rails.root.join("public", "logo.png")
      if File.exist?(logo_path)
        pdf.image logo_path.to_s, width: 110, position: :center
        pdf.move_down 4
      end

      pdf.fill_color BRAND_DARK
      pdf.font_size 14
      pdf.text CLINIC_NAME, align: :center, style: :bold

      pdf.fill_color BRAND_GREY
      pdf.font_size 9
      pdf.text CLINIC_TAGLINE, align: :center

      pdf.move_down 10

      # The "more formal-document feel" double rule. Prawn doesn't
      # have a native double-rule primitive; we draw two horizontal
      # strokes with a clearly visible gap. At 3pt the strokes
      # rendered too close together to read as two lines — bumped
      # to 8pt which is unambiguously a parallel pair.
      pdf.stroke_color BRAND_DARK
      pdf.line_width 0.75
      pdf.stroke_horizontal_rule
      pdf.move_down 8
      pdf.stroke_horizontal_rule
      pdf.line_width 1
      pdf.fill_color BODY_GREY
      pdf.move_down 18
    end

    def render_title(pdf)
      pdf.fill_color BODY_GREY
      pdf.font_size 16
      pdf.text title, style: :bold
      client_label = record.client_profile&.full_name
      if client_label
        pdf.fill_color BRAND_GREY
        pdf.font_size 10
        pdf.move_down 2
        pdf.text "Client: #{client_label}"
      end
      pdf.fill_color BODY_GREY
      pdf.move_down 8
    end

    # The diagonal centered watermark for unsigned records. Uses
    # Prawn's repeat(:all) so it lands on every page Prawn generates.
    # Drawn before the body so it's behind text (Prawn z-order is
    # draw-order).
    #
    # IMPORTANT centering math: Prawn's bounds.width / bounds.height
    # give the CONTENT area (inside margins), not the page itself.
    # With our 60/50/60/50 margins on A4 (595×842 pt), the content
    # box is 495×722, shifted +50/+60 from the page origin. Rotating
    # around bounds-center puts the pivot off-center on the page —
    # which is why the watermark drifted right in earlier renders.
    # Fix: rotate around the page absolute center (page_w/2, page_h/2),
    # which on A4 is (297.5, 421).
    def apply_watermark(pdf)
      pdf.repeat(:all) do
        pdf.fill_color "E2E8F0"  # slate-200 — light enough not to obscure text
        pdf.transparent(0.55) do
          # A4 page size in points (Prawn's default unit).
          page_w = 595.28
          page_h = 841.89
          text = "DRAFT — NOT FOR DISTRIBUTION"
          size = 48

          pdf.font_size(size) do
            text_w = pdf.width_of(text)
            # rotate(angle, origin:) rotates around the given POINT
            # in the canvas. We want the rotation pivot at the
            # absolute page center. We also need to position the
            # text so its center sits at that same point — meaning
            # we offset by half the text width to the left of the
            # pivot. The y baseline is set just below the pivot so
            # the text's vertical center aligns with the pivot
            # (rough rule of thumb: y = pivot - size/3).
            cx = page_w / 2.0
            cy = page_h / 2.0
            pdf.rotate(45, origin: [cx, cy]) do
              pdf.draw_text text,
                at: [cx - text_w / 2.0, cy - size / 3.0],
                size: size
            end
          end
        end
        pdf.fill_color BODY_GREY
      end
    end

    def render_footer_on_all_pages(pdf)
      generated_at = Time.current.strftime("%-d %b %Y")
      generated_by_name = generated_by&.full_name || "Cerca Africa staff"

      # Use number_pages to write per-page footer text. <page> and
      # <total> are Prawn's special placeholders for the current
      # page and total page count.
      footer_text =
        "Confidential — #{CLINIC_NAME}   ·   " \
        "Generated #{generated_at} by #{generated_by_name}   ·   " \
        "Page <page> of <total>"

      pdf.number_pages(
        footer_text,
        at: [0, -20],
        width: pdf.bounds.width,
        align: :center,
        size: 8,
        color: MUTED_GREY
      )
    end
  end
end
