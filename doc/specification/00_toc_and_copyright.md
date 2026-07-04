# Tungsten Programmer's Language

This document is a complete and concise specification of the syntax and semantics of the _[Tungsten Programming Language, version 2026.07.04][Release]_.

It may be of interest to implementers and users of Tungsten, as well as to those generally interested in modern programming language design. However, it is not a tutorial. Those wanting to learn Tungsten should start with _[The Tungsten Tutorial][Tutorial]_, before moving on to this work.

Syntax and lexical analysis are formally specified, the rest is described using precise but informal English.

Every implementation comes with a number of core classes, see _[The Tungsten Core][Core]_. These classes are mentioned only when they are relevant to the language itself.

<small>See the [changelog](CHANGELOG.md) for information on changes since this release.</small>

## Table of Contents

0. [Introduction](01_introduction.md)
1. [Lexical Analysis](02_lexical_analysis.md)
2. [Floating-Point Math Modes](floating-point-math.md)
3. Appendix
    A: [Units of measurement](appendix_units_of_measurement.md)
    B: [Inspiration](appendex_language_inspiration.md)

[Home]:     https://tungsten-lang.org/
[Docs]:     https://docs.tungsten-lang.org/2026.07.04/docs
[Release]:  https://docs.tungsten-lang.org/2026.07.04/release
[Core]:     https://docs.tungsten-lang.org/2026.07.04/core
[Tutorial]: https://docs.tungsten-lang.org/2026.07.04/tutorial

## Resources

* [The Tungsten Core][Core]
* [The Tungsten Tutorial][Tutorial]

See [tungsten-lang.org][Home] for more information and documentation.

## Copyright

<small>Many of the designations used by manufacturers and sellers to distinguish their products are claimed as trademarks. Where those designations appear in this document, and Spicywombat, LLC, was aware of a trademark claim, the designations have been printed in initial capital letters, in all capitals, or suffixed with the trademark (™) sign. Tungsten™ and Spicywombat™ are trademarks of Spicywombat, LLC.

<a rel="license" href="http://creativecommons.org/licenses/by-sa/4.0/"><img alt="Creative Commons License" style="border-width:0" src="http://i.creativecommons.org/l/by-sa/4.0/88x31.png" /></a>

This work is licensed under the Creative Commons Attribution-ShareAlike 4.0 International License.

To view a copy of this license, visit [creativecommons.org/licenses/by-sa/4.0/deed.en_US][License].

Every precaution was taken in the preparation of this document. However, the author assumes no responsibility for errors or omissions, or for damages that may result from the use of information (including source code) contained herein.

Copyright © 2013–2026 Erik Peterson. This document is licensed under the Creative Commons Attribution-ShareAlike 4.0 International License (CC BY-SA 4.0); you are free to share and adapt it, with attribution, under the same terms.

Made in America, released on its 250th birthday.

Version: 2026.07.04

[License]: http://creativecommons.org/licenses/by-sa/4.0/
</small>
