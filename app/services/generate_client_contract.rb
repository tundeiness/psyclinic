require "prawn"

# Generates a PDF copy of the Cerca Africa client services contract,
# personalized with the client's name. Returned as a binary string
# that the controller can stream as application/pdf.
#
# The contract text is the canonical policy document; this file is
# the single source of truth in the codebase. When the policy
# changes, update the text below AND bump
# AppSetting.current_contract_version so old signatures fall out of
# scope and clients are prompted to re-sign.
class GenerateClientContract
  CONTRACT_VERSION = "v1-2026".freeze

  # ─────────────────────────────────────────────────────────────────
  # POLICY TEXT (extracted from the official Cerca Africa PDF).
  # ─────────────────────────────────────────────────────────────────

  HEADER_LINES = [
    "Suite C2, Triple-H Plaza, Wuye, Abuja. Nigeria",
    "+234 807 361 0884, +234 813 261 2221",
    "www.cercaafrica.com  ·  service@cercaafrica.com"
  ].freeze

  WELCOME = <<~TXT.strip
    This document is a summary of our policies and will serve as a
    record of the terms of the therapeutic journey we are about to
    embark on together. Upon reading and accepting the contents, you
    will be required to sign at the end of the document as
    confirmation that you are comfortable and in agreement with the
    terms. You may ask questions to seek clarification on any terms.
  TXT

  SECTIONS = [
    {
      heading: "Our Services",
      body: <<~TXT.strip
        We offer a range of Psychological assessments and Interventions,
        including Psychotherapy, Lifestyle Medicine and Health Coaching.
        These are usually eclectic, tailored to the specific needs of
        the client, and vary with the personalities of the Client and
        Clinician. We primarily employ Cognitive Behaviour Therapy but
        also use tools from other models of therapy as needed.

        Psychotherapy, especially at the beginning, requires levels of
        openness and willingness to address personal challenges. This
        process can cause temporary feelings of vulnerability, sadness,
        worry, anger, guilt, fear, or any other forms of distress and
        may also seem to exacerbate symptoms because it may involve
        talking about experiences you may not have enjoyed or prefer
        not to talk about. But with time, clients are equipped with
        tools and techniques to live more fulfilled, healthier, and
        happier lives as shown by decades of research.

        For any treatment or intervention to be effective, the client
        must be actively committed throughout the process. This
        commitment involves, at the barest minimum, showing up on time
        for sessions and working on prescribed assignments as
        discussed before the next session.
      TXT
    },
    {
      heading: "Meetings",
      body: <<~TXT.strip
        • Sessions typically last 45 minutes to 1 hour and hold once
          weekly, at the same time every week; alternative arrangements
          can be agreed on where needed.
        • Sessions may be rescheduled, only up to 24 hours before the
          session. Failure to show up for a session without required
          notice will make the session count as held.
        • Where Client misses sessions for up to 3 weeks (with or
          without rescheduling), the objectives of therapy or coaching
          will be re-evaluated and reassessment of the Client may also
          be required.
        • Clients may take some "time off" for up to 6 weeks between
          sessions to address crucial personal decisions. Any leftover
          sessions will expire 6 weeks from the last session attended.
        • Client may choose to terminate therapy or coaching at any
          time, though at least 1 wrap-up session is recommended.
        • The Clinician is obliged to cancel the session if a client
          shows up under the influence of substances or in a fit of
          rage with tendencies to harm other persons.
      TXT
    },
    {
      heading: "Fees",
      body: <<~TXT.strip
        • In event of an emergency, Client is advised to call the
          Hotline of the required agency. For non-urgent, non-life
          threatening matters, the office may be called directly on
          +234 807 361 0884.
        • The Clinic charges N50,000 per assessment session. Subsequent
          individual therapy sessions are purchased in blocks of 6 at
          N300,000 per block, or a 60/40 installment plan: N180,000 up
          front and N120,000 after 3 sessions.
        • Sessions may be rescheduled up to 24 hours before they are
          due. Sessions not duly rescheduled will count as held.
        • Missing 3 consecutive sessions will lead to a review of
          therapy or coaching goals and subsequently, treatment plan.
        • Unattended sessions expire 6 weeks after the last session
          attended.
        • Session fees do not cover charges for paid psychological
          tools.
        • Psychological / Mental Health Reports may be requested by
          the Client, their employer, the Court or any other
          Organisations the Client is involved with. The Client's
          approval is sought before any reports are sent except in
          the case of the Court. Psychological Reports will be charged
          as required by assessments.
        • If the Client is involved in a Legal Case and the
          Psychologist is called to testify, the Client will be
          required to pay for the Psychologist's professional time
          including preparation and transportation costs even if the
          Psychologist was called by another party. Involvement in
          Legal proceedings is charged per case.
        • Except in cases where the Clinician is unavailable to
          provide services already paid for, all fees are
          non-refundable.
      TXT
    },
    {
      heading: "Confidentiality and Exceptions",
      body: <<~TXT.strip
        • Client Records (Clinic Card containing Biodata, medical
          information, details of attended appointments and so on)
          though protected by confidentiality are available to
          qualified personnel within the Clinic System.
        • Session reports and notes consisting of more detailed and
          personal information on the client's case are kept privately
          by the attending Clinician.
        • To provide the best possible services, the Psychologist may
          need to discuss Client's case with other Practitioners who
          are also bound by confidentiality; case details will be
          shared anonymously on such occasions.
        • Where Psychologist has reason to suspect that Client may
          bring harm to themselves or others, the Psychologist will
          contact the Police or Family members as required by Client's
          case.
        • Where the Psychologist discovers from information provided
          by the Client that someone else may be suffering Abuse, the
          Psychologist is required to report it to the appropriate
          organizations.
        • The Court may also order otherwise confidential information
          on Client be provided where Client is involved in a Court
          Case. The Psychologist is obligated by law to provide all
          required information in such situations.
        • Where Sponsors (including Parents) are involved, Sponsors
          will be given periodic updates on assessment and treatment
          as approved by the benefiting Client.
        • In Couple / Family / Group Sessions, attendees are asked to
          keep everything they learn from the sessions secret, but
          there is no way to guarantee that they do.
      TXT
    },
    {
      heading: "Other Points to Note",
      body: <<~TXT.strip
        • To protect the Client's confidentiality, Client may choose
          not to relate with the Psychologist if they meet at social
          gatherings or public settings outside the Clinic. "Public
          settings" here also extends to Social Media.
        • This contract is between the Client (and Sponsor, where
          applicable) and Cerca Africa Mind and Behaviour Clinic. No
          3rd party may enjoy the benefits of the terms of this
          contract. The contract is NOT transferable.
        • All other terms may be agreed on mutually as the therapy
          progresses.
        • In the unlikely event that conflicts arise in the course of
          therapy and they cannot be resolved, the Clinician is
          required to refer the Client to another Clinician.
      TXT
    }
  ].freeze

  def self.call(...) = new(...).call

  def initialize(client_profile:)
    @client_profile = client_profile
  end

  def call
    Prawn::Document.new(page_size: "A4", margin: 50) do |pdf|
      render_header(pdf)
      render_title(pdf)
      render_client_name(pdf)
      render_welcome(pdf)
      SECTIONS.each { |s| render_section(pdf, s) }
      render_signature_block(pdf)
    end.render
  end

  private

  def render_header(pdf)
    logo_path = Rails.root.join("public", "logo.png")
    if File.exist?(logo_path)
      pdf.image logo_path.to_s, width: 100
    end
    pdf.move_down 4
    HEADER_LINES.each do |line|
      pdf.text line, size: 8, color: "555555"
    end
    pdf.move_down 16
  end

  def render_title(pdf)
    pdf.text "Clinic Services Contract",
      size: 18, style: :bold, align: :center
    pdf.move_down 20
  end

  def render_client_name(pdf)
    pdf.text "Name of Client/Patient: " \
      "<b>#{@client_profile.full_name}</b>",
      inline_format: true, size: 11
    pdf.move_down 16
  end

  def render_welcome(pdf)
    pdf.text "Welcome to Cerca Africa Mind & Behaviour Clinic!",
      size: 12, style: :bold
    pdf.move_down 6
    pdf.text WELCOME, size: 10, leading: 2
    pdf.move_down 16
  end

  def render_section(pdf, section)
    pdf.text section[:heading], size: 12, style: :bold
    pdf.move_down 4
    pdf.text section[:body], size: 10, leading: 2
    pdf.move_down 14
  end

  def render_signature_block(pdf)
    pdf.move_down 20
    pdf.text "Signing below confirms that you have read, agree to, " \
             "and give consent to the execution of the terms " \
             "provided above.",
      size: 10, leading: 2, style: :italic
    pdf.move_down 24

    pdf.text "Client's Name: ___________________________________",
      size: 10
    pdf.move_down 16
    pdf.text "Client's Signature: _______________________________",
      size: 10
    pdf.move_down 16
    pdf.text "Date: _______________________",
      size: 10
    pdf.move_down 24

    pdf.text "Sponsor's Name (if applicable): __________________",
      size: 10
    pdf.move_down 16
    pdf.text "Sponsor's Signature: ____________________________",
      size: 10
    pdf.move_down 16
    pdf.text "Date: _______________________",
      size: 10
    pdf.move_down 30

    pdf.text "Contract version: #{CONTRACT_VERSION}",
      size: 8, color: "888888"
  end
end
