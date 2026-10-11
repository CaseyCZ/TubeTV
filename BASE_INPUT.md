# TubeTV — lokální základní vstup

TubeTV v1.0.0 a aktuální patch mapa jsou postavené proti jednomu ověřenému **YouTube tvOS 4.54.01** základnímu balíku.

Tento soubor je uložený **lokálně** a není součástí Git repozitáře. V `Masteru` jsou uložené jeho přesné fingerprinty, patch data a builder, takže lze vždy ověřit, že se používá správný základ.

## Referenční balík

- Lokální název souboru: `Tube.tipa`
- Velikost: `43 830 825` bajtů
- SHA-256 balíku: `48f65a92c87a36775ed8294a77994f0ad0f2c44a9fbf92bf2f4ca3a2acd3b514`
- App bundle: `Payload/YouTubeUnstable.app`
- Bundle identifier: `com.google.ios.youtube`
- Verze: `4.54.01`
- Executable: `YouTubeUnstable`
- Executable SHA-256: `2a1747008e4e9585bfd6b80fa180263395817415af1681c9090f12ba64f016da`
- Původní podporovaná zařízení: `AppleTV11,1`, `AppleTV6,2`

Fingerprint executable a patch metadata jsou také v `patches/youtube-4.54.01.json` a kontroluje je `tools/build_tubetv.py`.

## Doporučené lokální umístění

Nejjednodušší workflow je držet vlastní lokální kopii `Tube.tipa` přímo v kořeni lokálního klonu:

```text
TubeTV/
├── Tube.tipa                 # pouze lokálně
├── tools/
├── patches/
├── PATCHING.md
└── BASE_INPUT.md
```

Soubor je krytý `.gitignore`, takže se při běžném `git add` nepřidá do repozitáře.

Může být uložený i kdekoli jinde; builderu se pak předá plná cesta.

## Rebuild stabilní verze

Pokud je `Tube.tipa` v kořeni repozitáře:

```bash
python3 tools/build_tubetv.py Tube.tipa -o TubeTV-Stable.ipa
```

Pokud je uložená jinde:

```bash
python3 tools/build_tubetv.py /cesta/k/Tube.tipa -o TubeTV-Stable.ipa
```

S nezměněným stabilním patch setem builder ověří výsledný executable proti TubeTV v1.0.0 baseline.

## Pro další verze

Stejný lokální `Tube.tipa` zůstává referenčním základem i pro v1.0.1 a další verze, dokud se vědomě nerozhodneme přejít na jinou verzi YouTube tvOS.

Při přechodu na nový YouTube tvOS runtime musí vzniknout nový `BASE_INPUT` fingerprint, nová patch mapa a nové ověření offsetů. Staré 4.54.01 offsety se na jinou verzi nesmí automaticky přenášet.
