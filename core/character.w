# @todo singleton objects
#
+ Character
  alias :na      :unicode_name
  alias :na1     :unicode_1_name
  alias :blk     :block
  alias :gc      :general_category
  alias :sc      :script
  alias :bc      :bidirectional_category
  alias :ccc     :combining_class
  alias :dt      :decomposition_type
  alias :dm      :decomposition_mapping
  alias :lower   :lowercase
  alias :slc     :simple_lowercase_mapping
  alias :lc      :lowercase_mapping
  alias :upper   :uppercase
  alias :suc     :simple_uppercase_mapping
  alias :uc      :uppercase_mapping
  alias :stc     :simple_titlecase_mapping
  alias :tc      :titlecase_mapping
  alias :cf      :case_folding
  alias :ahex    :ascii_hex_digit
  alias :alpha   :alphabetic
  alias :bidi_c  :bidi_control
  alias :bidi_m  :bidi_mirrored
  alias :ce      :composition_exclusion
  alias :ci      :case_ignorable
  alias :comp_ex :full_composition_exclusion
  alias :cwcf    :changes_when_casefolded
  alias :cwcm    :changes_when_casemapped
  alias :cwkcf   :changes_when_nfkc_casefolded
  alias :cwl     :changes_when_lowercased
  alias :cwt     :changes_when_titlecased
  alias :cwu     :changes_when_uppercased
  alias :dep     :deprecated
  alias :di      :default_ignorable_code_point
  alias :dia     :diacritic
  alias :ea      :east_asian_width
  alias :ext     :extender
  alias :fc_nfkc :fc_nfkc_closure
  alias :gcb     :grapheme_cluster_break
  alias :gr_base :grapheme_base
  alias :gr_ext  :grapheme_extend
  alias :gr_link :grapheme_link
  alias :hex     :hex_digit
  alias :hst     :hangul_syllable_type
  alias :idc     :id_continue
  alias :ideo    :ideographic
  alias :ids     :id_start
  alias :idsb    :ids_binary_operator
  alias :idst    :ids_trinary_operator
  alias :inmc    :indic_mantra_category
  alias :insc    :indic_syllabic_category
  alias :isc     :iso_10646_comment
  alias :jg      :joining_group
  alias :join_c  :join_control
  alias :jsn     :jamo_short_name
  alias :jt      :joining_type
  alias :lb      :line_break
  alias :loe     :logical_order_exception
  alias :nchar   :noncharacter_code_point
  alias :nfc_qc  :nfc_quick_check
  alias :nfd_qc  :nfd_quick_check
  alias :nfkc_cf :nfkc_casefold
  alias :nfkc_qc :nfkc_quick_check
  alias :nfkd_qc :nfkd_quick_check
  alias :nt      :numeric_type
  alias :nv      :numeric_value
  alias :oalpha  :other_alphabetic
  alias :odi     :other_default_ignorable_code_point
  alias :ogr_ext :other_grapheme_extend
  alias :oidc    :other_id_continue
  alias :oids    :other_id_start
  alias :olower  :other_lowercase
  alias :omath   :other_math
  alias :oupper  :other_uppercase
  alias :pat_syn :pattern_syntax
  alias :pat_ws  :pattern_white_space
  alias :qmark   :quotation_mark
  alias :sb      :sentence_break
  alias :scf     :simple_case_folding
  alias :scx     :script_extension
  alias :sd      :soft_dotted
  alias :term    :terminal_punctuation
  alias :uideo   :unified_ideograph
  alias :vs      :variation_selector
  alias :wb      :word_break
  alias :wspace  :white_space
  alias :xidc    :xid_continue
  alias :xids    :xid_start
  alias :xo_nfc  :expands_on_nfc
  alias :xo_nfd  :expands_on_nfd
  alias :xo_nfkc :expands_on_nfkc
  alias :xo_nfkd :expands_on_nfkd

  -> new
    @data
      abbreviations: %w[LF NL EOL]
      age:       1.1
      aliases:   ["LINE FEED (LF)", "new line (NL)", "end of line (EOL)"]
      block:     "ASCII"
      bytes:     "<<0A>>"
      codepoint: "<<00,0A>>"
      control:   ["LINE FEED", "NEW LINE", "END OF LINE"]
      digraph:   "LF"
      escapes:
        c:          "\\u000A"
        css:        "\\00000A"
        html:       "&#000A;"
        java:       "\\uA"
        javascript: "\\uA"
        json:       "\\uA"
        perl:       "\\x{A}"
        python:     "\\u000A"
        rfc5137:    "\\u'A'"
        ruby:       "\\u{A}"
        url:        "%0A"
      general_category: "Control"
      name:   "LINE FEED (LF)"
      script: "Common"
      wrong_iso8851_1_mojibake: "â"

  # @todo make promise <- load_data
  :memoize
  :eager
  -> data
    CharacterMeta.new(self)

  -> name
    unicode_name or unicode_1_name

  -> is_alnum?
  -> is_alpha?
  -> is_ascii?
  -> is_cntrl?
  -> is_digit?
  -> is_graph?
  -> is_lower?
  -> is_match?
  -> is_number?
  -> is_print?
  -> is_punct?
  -> is_space?
  -> is_upper?
  -> is_valid?
  -> is_xdigit?

  -> printable?
    true

  -> method_missing(name: Symbol)
    super unless @data.has_key?(name)
    @data[name]
