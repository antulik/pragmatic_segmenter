# -*- encoding : utf-8 -*-
require 'pragmatic_segmenter/cleaner'
require 'pragmatic_segmenter/list'
require 'pragmatic_segmenter/abbreviation'

module PragmaticSegmenter
  # This class segments a text into an array of sentences.
  class Segmenter
    PUNCT = ['。', '．', '.', '！', '!', '?', '？']
    PUNCT_AR = ['?', '!', ':', '.', '؟', '،']
    PUNCT_FA = ['?', '!', ':', '.', '؟']
    PUNCT_UR = ['?', '!', '۔', '؟']
    PUNCT_HI = ['।', '|', '.', '!', '?']
    PUNCT_HY = ['։', '՜', ':']
    PUNCT_EL = ['.', '!', ';', '?']
    PUNCT_MY = ['။', '၏', '?', '!']
    PUNCT_AM = ['።', '፧', '?', '!']

    attr_reader :language, :doc_type
    def initialize(text:, **args)
      return [] if text.nil?
      if args[:clean].eql?(false)
        @text = text.dup
      else
        @text = PragmaticSegmenter::Cleaner.new(text: text.dup, language: args[:language], doc_type: args[:doc_type]).clean
      end
      if args[:language].nil?
        @language = 'en'
      else
        @language = args[:language]
      end
      @doc_type = args[:doc_type]
    end

    # Segment a text into an array of sentences
    #
    # Example:
    #   >> PragmaticSegmenter::Segment(text: "Hello world. My name is Kevin.").segment
    #   => ["Hello world.", "My name is Kevin."]
    #
    # Arguments:
    #    text:       (String)  *required
    #    language:   (String)  *optional
    #                (two-digit ISO 639-1 code e.g. 'en')
    #    doc_type:   (String)  *optional
    #                (e.g. 'pdf')
    #    clean:      (Boolean) *true unless specified

    def segment
      return [] if @text.nil?
      @text = PragmaticSegmenter::List.new(text: @text).add_line_break
      process_abbr
      numbers
      multi_period_abbr
      abbr_as_sentence_boundary
      geo_location
      split_lines
    end

    private

    def process_abbr
      original = @text.dup

      # Rubular: http://rubular.com/r/yqa4Rit8EY
      # any possessive abbreviations (i.e. JFK Jr.'s)
      @text.gsub!(/\.(?='s\s)|\.(?='s$)|\.(?='s\z)/, '∯')

      # any single upper case letter followed by a period is not a sentence ender
      # usually upper case letters are initials in a name
      # Rubular: http://rubular.com/r/e3H6kwnr6H
      @text.gsub!(/(?<=^[A-Z])\.(?=\s)/, '∯')
      # Rubular: http://rubular.com/r/gitvf0YWH4
      @text.gsub!(/(?<=\s[A-Z])\.(?=\s)/, '∯')
      if language.eql?('de') || language.eql?('fr')
        # Rubular: http://rubular.com/r/B4X33QKIL8
        @text.gsub!(/(?<=\s[a-z])\.(?=\s)/, '∯') # German test #011, #013, #018, #019, #023
        # Rubular: http://rubular.com/r/iUNSkCuso0
        @text.gsub!(/(?<=^[a-z])\.(?=\s)/, '∯') # German test #032
      end
      downcased = @text.downcase
      abbr = PragmaticSegmenter::Abbreviation.new(language: language)
      abbr.all.each do |a|
        next unless downcased.include?(a.strip)
        abbrev_match = original.scan(/(?:^|\s|\r|\n)#{Regexp.escape(a.strip)}/i)
        next if abbrev_match.empty?
        next_word_start = /(?<=#{Regexp.escape(a.strip)} ).{1}/
        character_array = @text.scan(next_word_start)
        abbrev_match.each_with_index do |am, index|
          if language.eql?('de')
            @text.gsub!(/(?<=#{am})\.(?=\s)/, '∯')
          elsif language.eql?('ar') || language.eql?('fa')
            @text.gsub!(/(?<=#{am})\./, '∯')
          else
            character = character_array[index]
            prefix = abbr.prefix
            number_abbr = abbr.number
            upper = /[[:upper:]]/.match(character.to_s)
            if upper.nil? || prefix.include?(am.downcase.strip)
              if prefix.include?(am.downcase.strip)
                @text.gsub!(/(?<=#{am.strip})\.(?=\s)/, '∯')
              elsif number_abbr.include?(am.downcase.strip)
                @text.gsub!(/(?<=#{am.strip})\.(?=\s\d)/, '∯')
                @text.gsub!(/(?<=#{am.strip})\.(?=\s+\()/, '∯')
              else
                if language.eql?('ru')
                  @text.gsub!(/(?<=\s#{am.strip})\./, '∯')
                  @text.gsub!(/(?<=\A#{am.strip})\./, '∯')
                  @text.gsub!(/(?<=^#{am.strip})\./, '∯')
                else
                  @text.gsub!(/(?<=#{am.strip})\.(?=((\.|:|\?)|(\s([a-z]|I\s|I'm|I'll|\d))))/, '∯')
                  @text.gsub!(/(?<=#{am.strip})\.(?=,)/, '∯')
                end
              end
            end
          end
        end
      end
    end

    def abbr_as_sentence_boundary
      # Find the most common cases where abbreviations double as sentence boundaries.
      %w(A Being Did For He How However I In Millions More She That The There They We What When Where Who Why).each do |word|
        @text.gsub!(/U∯S∯\s#{Regexp.escape(word)}\s/, "U∯S\.\s#{Regexp.escape(word)}\s")
        @text.gsub!(/U\.S∯\s#{Regexp.escape(word)}\s/, "U\.S\.\s#{Regexp.escape(word)}\s")
        @text.gsub!(/U∯K∯\s#{Regexp.escape(word)}\s/, "U∯K\.\s#{Regexp.escape(word)}\s")
        @text.gsub!(/U\.K∯\s#{Regexp.escape(word)}\s/, "U\.K\.\s#{Regexp.escape(word)}\s")
        @text.gsub!(/E∯U∯\s#{Regexp.escape(word)}\s/, "E∯U\.\s#{Regexp.escape(word)}\s")
        @text.gsub!(/E\.U∯\s#{Regexp.escape(word)}\s/, "E\.U\.\s#{Regexp.escape(word)}\s")
        @text.gsub!(/U∯S∯A∯\s#{Regexp.escape(word)}\s/, "U∯S∯A\.\s#{Regexp.escape(word)}\s")
        @text.gsub!(/U\.S\.A∯\s#{Regexp.escape(word)}\s/, "U\.S\.A\.\s#{Regexp.escape(word)}\s")
        @text.gsub!(/I∯\s#{Regexp.escape(word)}\s/, "I\.\s#{Regexp.escape(word)}\s")
      end
    end

    def geo_location
      # Rubular: http://rubular.com/r/G2opjedIm9
      @text.gsub!(/(?<=[a-zA-z]°)\.(?=\s*\d+)/, '∯')
    end

    def replace_ellipsis(line)
      # http://www.dailywritingtips.com/in-search-of-a-4-dot-ellipsis/
      # http://www.thepunctuationguide.com/ellipses.html

      # Rubular: http://rubular.com/r/YBG1dIHTRu
      line.gsub!(/(\s\.){3}\s/, '♟')

      # Rubular: http://rubular.com/r/2VvZ8wRbd8
      line.gsub!(/(?<=[a-z])(\.\s){3}\.(\z|$|\n)/, '♝')

      # Rubular: http://rubular.com/r/Hdqpd90owl
      line.gsub!(/(?<=\S)\.{3}(?=\.\s[A-Z])/, 'ƪ')

      # Rubular: http://rubular.com/r/i60hCK81fz
      line.gsub!(/\.\.\.(?=\s+[A-Z])/, '☏.')
      line.gsub!(/\.\.\./, 'ƪ')
      line
    end

    def analyze_lines(line:, segments:)
      line.gsub!(/\n/, 'ȹ')
      line = replace_ellipsis(line)

      # account for periods in email addresses
      line.gsub!(/(\w)(\.)(\w)/, '\1∮\3')

      clause_1 = false
      end_punc_check = false
      if language
        punctuation =
          Segmenter.const_defined?("PUNCT_#{language.upcase}") ? Segmenter.const_get("PUNCT_#{language.upcase}") : PUNCT
      else
        punctuation = PUNCT
      end
      punctuation.each do |p|
        end_punc_check = true if line[-1].include?(p)
        clause_1 = true if line.include?(p)
      end
      if clause_1
        line << 'ȸ' unless end_punc_check || language.eql?('ar') || language.eql?('fa')
        copy_l = line
        if language == 'de'
          if copy_l.include?('„')
            btwn_dbl_quote = copy_l.scan(/„(?>[^“\\]+|\\{2}|\\.)*“/)
            copy_l.scan(/\A„(?>[^“\\]+|\\{2}|\\.)*“/).each do |q|
              btwn_dbl_quote << q
            end
          elsif copy_l.include?(',,')
            btwn_dbl_quote = copy_l.scan(/,,(?>[^“\\]+|\\{2}|\\.)*“/)
          end
        else
          btwn_dbl_quote = copy_l.scan(/"(?>[^"\\]+|\\{2}|\\.)*"/)
        end
        # Rubular: http://rubular.com/r/2YFrKWQUYi
        btwn_sngl_quote = copy_l.scan(
          /(?<=\s)'(?:[^']|'[a-zA-Z])*'/)
        btwn_jp_quote = copy_l.scan(
          /\u{300c}(?>[^\u{300c}\u{300d}\\]+|\\{2}|\\.)*\u{300d}/)
        btwn_parens = copy_l.scan(
          /\((?>[^\(\)\\]+|\\{2}|\\.)*\)/)
        btwn_jp_parens = copy_l.scan(
          /\u{ff08}(?>[^\u{ff08}\u{ff09}\\]+|\\{2}|\\.)*\u{ff09}/)
        btwn_ru_quote = copy_l.scan(/«(?>[^»\\]+|\\{2}|\\.)*»/)
        btwn_dbl_spec_quote = copy_l.scan(/”(?>[^”\\]+|\\{2}|\\.)*”/)
        btwn_dbl_spec_2_quote = copy_l.scan(/“(?>[^”\\]+|\\{2}|\\.)*”/)
        words_with_exclamations = ['!Xũ', '!Kung', 'ǃʼOǃKung', '!Xuun', '!Kung-Ekoka', 'ǃHu', 'ǃKhung', 'ǃKu', 'ǃung', 'ǃXo', 'ǃXû', 'ǃXung', 'ǃXũ', '!Xun', 'Yahoo!', 'Y!J', 'Yum!']
        words_with_exclamations.each do |exclamation|
          exclam_abbr = copy_l.scan(/#{Regexp.escape(exclamation)}/)
          sub_punct(exclam_abbr, line)
        end
        sub_punct(btwn_dbl_spec_quote, line)
        sub_punct(btwn_dbl_spec_2_quote, line)
        sub_punct(btwn_ru_quote, line)
        sub_punct(btwn_dbl_quote, line)
        sub_punct(btwn_sngl_quote, line)
        sub_punct(btwn_jp_quote, line)
        sub_punct(btwn_parens, line)
        sub_punct(btwn_jp_parens, line)
        line = line.gsub(/\?!/, '☉') if line.include?('?!')
        line = line.gsub(/!\?/, '☈') if line.include?('!?')
        line = line.gsub(/\?\?/, '☇') if line.include?('??')
        line = line.gsub(/!!/, '☄') if line.include?('!!')
        case
        when language.eql?('ar')
          line.gsub!(/(?<=\d):(?=\d)/, '♭')
          line.gsub!(/،(?=\s\S+،)/, '♬')
          subline = line.scan(/.*?[:\.!\?؟،]|.*?\z|.*?$/)
        when language.eql?('fa')
          line.gsub!(/(?<=\d):(?=\d)/, '♭')
          line.gsub!(/،(?=\s\S+،)/, '♬')
          subline = line.scan(/.*?[:\.!\?؟]|.*?\z|.*?$/)
        when language.eql?('hi')
          subline = line.scan(/.*?[।\|!\?]|.*?$/)
        when language.eql?('hy')
          subline = line.scan(/.*?[։՜:]|.*?$/)
        when language.eql?('el')
          subline = line.scan(/.*?[\.;!\?]|.*?$/)
        when language.eql?('my')
          subline = line.scan(/.*?[။၏!\?]|.*?$/)
        when language.eql?('am')
          subline = line.scan(/.*?[፧።!\?]|.*?$/)
        when language.eql?('ur')
          subline = line.scan(/.*?[۔؟!\?]|.*?$/)
        else
          line.gsub!(/\?(?=(\'|\"))/, 'ᓷ')
          line.gsub!(/\!(?=(\'|\"))/, 'ᓴ')
          line.gsub!(/\!(?=\s[a-z])/, 'ᓴ')
          line.gsub!(/\!(?=\,\s[a-z])/, 'ᓴ')
          subline = line.scan(/\u{ff08}(?:[^\u{ff09}])*\u{ff09}(?=\s?[A-Z])|\u{300c}(?:[^\u{300d}])*\u{300d}(?=\s[A-Z])|\((?:[^\)])*\)(?=\s[A-Z])|'(?:[^'])*'(?=\s[A-Z])|"(?:[^"])*"(?=\s[A-Z])|“(?:[^”])*”(?=\s[A-Z])|\S.*?[。．.！!?？ȸȹ☉☈☇☄]/)
        end
        subline.each_with_index do |s_l|
          segments << sub_symbols(s_l)
        end
      else
        line.gsub!(/ȹ/, "\n")
        line.gsub!(/∯/, '.')
        segments << line
      end
      new_array = []
      segments.each do |s|
        if s =~ /\.“\s[A-Z]/
          s.scan(/\.“\s[A-Z]/).each do |new_s|
            new_array << new_s
          end
        else
          new_array << s
        end
      end
    end

    def sub_symbols(text)
      text.gsub(/∯/, '.').gsub(/♬/, '،').gsub(/♭/, ':').gsub(/ᓰ/, '。').gsub(/ᓱ/, '．')
          .gsub(/ᓳ/, '！').gsub(/ᓴ/, '!').gsub(/ᓷ/, '?').gsub(/ᓸ/, '？').gsub(/☉/, '?!')
          .gsub(/☈/, '!?').gsub(/☇/, '??').gsub(/☄/, '!!').delete('ȸ').gsub(/ȹ/, "\n")
    end

    def numbers
      # Rubular: http://rubular.com/r/UL9LLoDJMs
      @text.gsub!(/(?<=\d)[.](?=\S)|[.](?=\d)/, '∯')

      # Rubular: http://rubular.com/r/rf4l1HjtjG
      @text.gsub!(/(?<=\r\d)\.(?=(\s\S)|\))/, '∯')

      # Rubular: http://rubular.com/r/HPa4sdc6b9
      @text.gsub!(/(?<=^\d)\.(?=(\s\S)|\))/, '∯')

      # Rubular: http://rubular.com/r/NuvWnKleFl
      @text.gsub!(/(?<=^\d\d)\.(?=(\s\S)|\))/, '∯')

      if language.eql?('de')
        # Rubular: http://rubular.com/r/hZxoyQwKT1
        @text.gsub!(/(?<=\s[0-9]|\s([1-9][0-9]))\.(?=\s)/, '∯')

        # Rubular: http://rubular.com/r/ityNMwdghj
        @text.gsub!(/(?<=-[0-9]|-([1-9][0-9]))\.(?=\s)/, '∯')
      end
    end

    def multi_period_abbr
      # It has a multi-period abbreviation like: U.S.A. or J.C. Penney
      # Rubular: http://rubular.com/r/xDkpFZ0EgH
      mpa = @text.scan(/\b[a-z](?:\.[a-z])+[.]/i)
      unless mpa.empty?
        mpa.each do |r|
          @text.gsub!(/#{Regexp.escape(r)}/, "#{r.gsub!('.', '∯')}")
        end
      end

      # Rubular: http://rubular.com/r/Vnx3m4Spc8
      @text.gsub!(/(?<=a∯m)∯(?=\s[A-Z])/, '.')
      @text.gsub!(/(?<=A∯M)∯(?=\s[A-Z])/, '.')
      @text.gsub!(/(?<=p∯m)∯(?=\s[A-Z])/, '.')
      @text.gsub!(/(?<=P∯M)∯(?=\s[A-Z])/, '.')
    end

    def sub_punct(array, content)
      return if array.nil?
      return if array.empty?
      content.gsub!('(', '\\(')
      content.gsub!(')', '\\)')
      content.gsub!(']', '\\]')
      content.gsub!('[', '\\[')
      content.gsub!('-', '\\-')
      array.each do |a|
        a.gsub!('(', '\\(')
        a.gsub!(')', '\\)')
        a.gsub!(']', '\\]')
        a.gsub!('[', '\\[')
        a.gsub!('-', '\\-')

        if a.include?('.')
          sub = a.gsub('.', '∯')
        else
          sub = a
        end

        content.gsub!(/#{Regexp.escape(a)}/, "#{sub}")

        if a.include?('。')
          sub_1 = sub.gsub('。', 'ᓰ')
        else
          sub_1 = sub
        end
        content.gsub!(/#{Regexp.escape(sub)}/, "#{sub_1}")

        if a.include?('．')
          sub_2 = sub_1.gsub('．', 'ᓱ')
        else
          sub_2 = sub_1
        end
        content.gsub!(/#{Regexp.escape(sub_1)}/, "#{sub_2}")

        if a.include?('！')
          sub_3 = sub_2.gsub('！', 'ᓳ')
        else
          sub_3 = sub_2
        end
        content.gsub!(/#{Regexp.escape(sub_2)}/, "#{sub_3}")
        if a.include?('!')
          sub_4 = sub_3.gsub('!', 'ᓴ')
        else
          sub_4 = sub_3
        end
        content.gsub!(/#{Regexp.escape(sub_3)}/, "#{sub_4}")

        if a.include?('?')
          sub_5 = sub_4.gsub('?', 'ᓷ')
        else
          sub_5 = sub_4
        end
        content.gsub!(/#{Regexp.escape(sub_4)}/, "#{sub_5}")

        if a.include?('？')
          sub_6 = sub_5.gsub('？', 'ᓸ')
        else
          sub_6 = sub_5
        end
        content.gsub!(/#{Regexp.escape(sub_5)}/, "#{sub_6}")

      end
      content.gsub!('\\(', '(')
      content.gsub!('\\)', ')')
      content.gsub!('\\[', '[')
      content.gsub!('\\]', ']')
      content.gsub!('\\-', '-')
      content
    end

    def split_lines
      segments = []
      lines = @text.split("\r")
      lines.each do |l|
        next if l == ''
        analyze_lines(line: l, segments: segments)
      end
      sentence_array = []
      segments.each_with_index do |line|
        next if line.gsub(/_{3,}/, '').length.eql?(0) || line.length < 2
        line = reinsert_ellipsis(line)
        # remove extra white space
        line.gsub!(/\s{3,}/, ' ')
        if line =~ /[!?\.][\"\'\“]\s{1}[A-Z]/
          subline = line.split(/(?<=[!?\.][\"\'\“])\s{1}(?=[A-Z])/)
          subline.each do |s|
            sentence_array << s
          end
        else
          sentence_array << line.tr("\n", '').strip
        end
      end
      sentence_array.reject{ |e| e.empty? }
    end

    def reinsert_ellipsis(line)
      line.gsub!(/ƪ/, '...')
      line.gsub!(/♟/, ' . . . ')
      line.gsub!(/♝/, '. . . .')
      line.gsub!(/☏/, '..')
      line.gsub!(/∮/, '.')
      line
    end
  end
end