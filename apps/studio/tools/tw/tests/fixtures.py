"""Small synthetic assets; no personal files, downloads or system font fallback."""
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen


def font(path):
    cps=[0x12000,0x13000,0x10b00,0x10b01,0x103a0,0x103a1,0x5d0,0x5d1,0x5b0]
    names=['.notdef']+[f'u{cp:X}' for cp in cps]
    builder=FontBuilder(1000,isTTF=True)
    builder.setupGlyphOrder(names)
    builder.setupCharacterMap(dict(zip(cps,names[1:])))
    glyphs={}
    for index,name in enumerate(names):
        pen=TTGlyphPen(None)
        pen.moveTo((50,0)); pen.lineTo((500,0)); pen.lineTo((150+index*12,700)); pen.closePath()
        glyphs[name]=pen.glyph()
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics({name:(600,50) for name in names})
    builder.setupHorizontalHeader(ascent=800,descent=-200)
    builder.setupNameTable(dict(familyName='AV Fixture',styleName='Regular',uniqueFontIdentifier='AVFixture',fullName='AV Fixture',psName='AVFixture'))
    builder.setupOS2(sTypoAscender=800,sTypoDescender=-200,usWinAscent=800,usWinDescent=200)
    builder.setupPost(); builder.setupMaxp(); builder.save(path)
