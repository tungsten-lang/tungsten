# Country Data
# http://data.okfn.org/data/core/country-codes#data
#
# Currency Data
# http://openexchangerates.org/
# http://exchangerate-api.com/
+ Locale
  attr :currency
  attr :position, in: %i[before after]
  attr :separators

Tungsten.locales
  en_US:
    currency: $ USD
    windows_id: 0x409

    script:
      - Latn
      - Latin

    # Narrow Short Abbr Long
    days:
      - S Su Sun Sunday
      - M Mo Mon Monday
      - T Tu Tue Tuesday
      - W We Wed Wednesday
      - T Th Thu Thursday
      - F Fr Fri Friday
      - S Sa Sat Saturday

    # Narrow Abbr Long
    months:
      - J Jan January
      - F Feb February
      - M Mar March
      - A Apr April
      - M May May
      - J Jun June
      - J Jul July
      - A Aug August
      - S Sep September
      - O Oct October
      - N Nov November
      - D Dec December

    ampm:
      - am AM
      - pm PM

    # Narrow Short Long
    eras:
      - B BC Before Christ
      - A AD Anno Domini

    patterns:
      times:
        - "h:mm a"
        - "h:mm:ss a"
        - "h:mm:ss a z"
        - "h:mm:ss a zzzz"

      dates:
        - "M/d/yy"
        - "MMM d, y"
        - "MMMM d, y"
        - "EEEE, MMMM d, y"

      datetime: "[date], [time]"

      decimal:   9,990.00
      currency: $9,990.00
      percent:   9,990%

    first_day: Sunday
    first_week_days: 1

    languages:
      aa: Afar
      ab: Abkhazian
      ace: Achinese
      ach: Acoli
      ada: Adangme
      ady: Adyghe
      ae: Avestan
      aeb: Tunisian Arabic
      af: Afrikaans
      afh: Afrihili
      agq: Aghem
      ain: Ainu
      ak: Akan
      akk: Akkadian
      akz: Alabama
      ale: Aleut
      aln: Gheg Albanian

    regions:
      001: World
      002: Africa
      003: North America
      005: South America
      009: Oceania
      011: Western Africa
      013: Central America
      014: Eastern Africa
      015: Northern Africa
      017: Middle Africa
      018: Southern Africa
      019: Americas
      021: Northern America
      029: Caribbean
      030: Eastern Asia
      034: Southern Asia
      035: Southeast Asia
      039: Southern Europe
      053: Australasia
      054: Melanesia
      057: Micronesian Region
      061: Polynesia
      142: Asia
      143: Central Asia
      145: Western Asia
      150: Europe
      151: Eastern Europe
      154: Northern Europe
      155: Western Europe
      419: Latin America
      AC: Ascension Island
      AD: Andorra
      AE: United Arab Emirates
      AF: Afghanistan
      AG: Antigua & Barbuda
      AI: Anguilla
      AL: Albania
      AM: Armenia
      AN: Netherlands Antilles
      AO: Angola
      AQ: Anarctica
      AR: Argentina
      AS: American Samoa
      AT: Austria
      AU: Australia
      AW: Aruba
      AX: Åland Islands
      AZ: Azerbaijan

  fr_FR:
    currency: € EUR euros

    windows_id: 0x40c

    languages:
      aa:  afar
      ab:  abkhaze
      ace: aceh
      ach: acoli
      ada: adangme
      ady: adyghéen
      ae:  avestique
      af:  afrikaans

    scripts:
      Arab: arabe
      Armi: araméen impérial
      Armn: arménien
      Avst: avestique

    regions:
      001: Monde
      002: Afrique
      003: Amérique du Nord
      005: Amérique du Sud
      US:  États-Unis

    days:
      - D dim. dimanche
      - L lun. lundi
      - M mar. mardi
      - M mer. mercredi
      - J jeu. jeudi
      - V ven. vendredi
      - S sam. samedi

    months:
      - J janv. janvier
      - F févr. février
      - M mars  mars
      - A avr.  avril
      - M mai   mai
      - J juin  juin
      - J juil. juillet
      - A août  août
      - S sept. septembre
      - O oct.  octobre
      - N nov.  novembre
      - D déc.  décembre

    ampm:
      - am AM
      - pm PM

    eras:
      - - av. J.-C.
        - av. J.-C.
        - avant Jésus-Christ

      - - ap. J.-C.
        - ap. J.-C.
        - après Jésus-Christ

    patterns:
      times:
        - "HH:mm"
        - "HH:mm:ss"
        - "HH:mm:ss z"
        - "HH:mm:ss zzzz"

      dates:
        - "dd/MM/y"
        - "d MMM y"
        - "d MMMM y"
        - "EEEE d MMMM y"

      datetime: "[date] 'à' [time]"

      decimal:  9 990,99
      currency: 9 990,99 €
      percent:  9 990 %

    first_day: Monday
    first_week_days: 4

  hi_IN:
    currency: ₹ INR

    windows_id: 0x439

    script:
      - Deva
      - Devanagari

    days:
      - र रवि  रविवार
      - सो सोम  सोमवार
      - मं मंगल मंगलवार
      - बु बुध  बुधवार
      - गु गुरु  गुरुवार
      - शु शुक्र शुक्रवार
      - श शनि  शनिवार

    months:
      - ज जन   जनवरी
      - फ़ फ़र   फ़रवरी
      - मा मार्च  मार्च
      - अ अप्रैल अप्रैल
      - म मई   मई
      - जू जून   जून
      - जु जुल   जुलाई
      - अ अग   अगस्त
      - सि सित   सितंबर
      - अ अक्तू  अक्तूबर
      - न नव   नवंबर
      - दि दिस   दिसंबर

    ampm:
      - am पूर्वाह्न
      - pm अपराह्न

    eras:
      - ईसा-पूर्व ईसा-पूर्व ईसा-पूर्व
      - ईस्वी    ईस्वी    ईसवी सन

    patterns:
      times:
        - "h:mm a"
        - "h:mm:ss a"
        - "h:mm:ss a z"
        - "h:mm:ss a zzzz"
      dates:
        - "d/M/yy"
        - "dd/MM/y"
        - "d MMMM y"
        - "EEEE, d MMMM y"

      datetime: "[date], [time]"

      decimal:   "9,99,990.999"
      currency: "₹9,99,990.00"
      percent:   "9,99,990%"

    languages:
      aa:  अफ़ार
      ab:  अब्ख़ाज़ियन
      ace: अचाइनीस
      ach: अकोली

    scripts:
      Arab: अरबी
      Armi: इम्पिरियल आर्मेनिक
      Armn: आर्मेनियाई
      Avst: अवेस्तन

    regions:
      001: विश्व
      002: अफ़्रीका
      US:  संयुक्त राज्य

  it_IT:
    script:
      - Latn
      - Latin

    days:
      - D dom domenica
      - L lun lunedì
      - M mar martedì
      - M mer mercoledì
      - G gio giovedì
      - V ven venerdì
      - S sab sabato

    months:
      - G gen gennaio
      - F feb febbraio
      - M mar marzo
      - A apr aprile
      - M mag maggio
      - G giu giugno
      - L lug luglio
      - A ago agosto
      - S set settembre
      - O ott ottobre
      - N nov novembre
      - D dic dicembre

    languages:
      aa:  afar
      ab:  abcaso
      ace: accinese
      ach: acioli
      ada: adangme
      ady: adyghe

    scripts:
      Afak: afaka
      Arab: arabo
      Armi: aramaico imperiale
      Armn: armeno
      Avst: avestico

    regions:
      001: Mondo
      002: Africa
      003: Nord America
      005: America del Sud
      009: Oceania
