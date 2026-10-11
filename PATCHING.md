# TubeTV — build a vývojový návod

Tento dokument popisuje aktuální workflow TubeTV od stabilní verze **v1.0.0** dál. Aktivní implementace je uložená v `Masteru` jako reprodukovatelný patch set pro ověřený **YouTube tvOS 4.54.01** runtime.

## Co je v repozitáři

V `Masteru` je uložený kompletní TubeTV-specifický zdroj potřebný pro další opravy a verze:

- `tools/build_tubetv.py` — builder pro IPA/TIPA vstup
- `patches/tubetv-stable-v1.js` — přesná TubeTV/TizenTube JavaScript injekce použitá ve v1.0.0
- `patches/youtube-4.54.01.json` — fingerprinty, code-cave layout a ARM64 patch pozice
- `patches/youtube-4.54.01-native.hex` — native support blok použitého stabilního patche
- `patches/README.md` — technické poznámky a reprodukční hashe
- `BASE_INPUT.md` — přesná identifikace podporovaného lokálního `Tube.tipa`

## Co zůstává lokálně

Základní balík **`Tube.tipa`** s YouTube tvOS 4.54.01 runtime je uložený lokálně a není commitovaný do Git repozitáře.

Doporučené lokální rozložení:

```text
TubeTV/
├── Tube.tipa                 # lokální základní balík
├── tools/
│   └── build_tubetv.py
├── patches/
├── PATCHING.md
└── BASE_INPUT.md
```

`.gitignore` záměrně ignoruje `*.ipa` a `*.tipa`, takže lokální vstup ani vygenerované IPA nejdou omylem commitnout.

## Ověřený základní soubor

Referenční vstup pro TubeTV v1.0.0:

```text
Soubor: Tube.tipa
Velikost: 43 830 825 bajtů
SHA-256: 48f65a92c87a36775ed8294a77994f0ad0f2c44a9fbf92bf2f4ca3a2acd3b514
Verze: YouTube tvOS 4.54.01
Bundle ID: com.google.ios.youtube
Executable SHA-256: 2a1747008e4e9585bfd6b80fa180263395817415af1681c9090f12ba64f016da
```

Stejné hodnoty jsou v **[BASE_INPUT.md](BASE_INPUT.md)** a builder je používá při validaci vstupu.

## Vytvoření aktuální stabilní IPA

Pokud je `Tube.tipa` v kořeni lokálního klonu repozitáře:

```bash
python3 tools/build_tubetv.py Tube.tipa -o TubeTV-Stable.ipa
```

Pokud je uložená jinde:

```bash
python3 tools/build_tubetv.py /cesta/k/Tube.tipa -o TubeTV-Stable.ipa
```

Builder před úpravou kontroluje:

1. SHA-256 celého vstupního balíku,
2. YouTube tvOS verzi `4.54.01`,
3. původní bundle identifier `com.google.ios.youtube`,
4. SHA-256 hlavního executable,
5. očekávané bajty na všech native patch pozicích.

Pokud je archiv pouze znovu zabalený, ale obsahuje stejný ověřený executable a metadata, builder upozorní na rozdílný fingerprint balíku a pokračuje v ověření samotného obsahu.

## Kontrola stabilní v1.0.0

Při použití nezměněného `patches/tubetv-stable-v1.js` musí výsledný executable odpovídat stabilnímu baseline:

```text
377c21b1620de9248574d008832dff1c7b25ad30ce48047ac3323f66f409b22c
```

Tento executable i výsledný `Info.plist` byly porovnány s publikovanou `TubeTV-Stable.ipa` v release v1.0.0 a odpovídají stabilnímu sestavení.

## Co builder mění

Builder zachová YouTube tvOS 4.54.01 runtime/player a provede TubeTV změny:

- změní bundle identifier na `cz.caseycz.tubetv`
- nastaví název aplikace na `TubeTV`
- zachová / doplní podporu `AppleTV5,3`, `AppleTV6,2` a `AppleTV11,1`
- aplikuje ověřené Cobalt/native hooky
- vloží zvolený TubeTV JS patch do rezervované JS oblasti
- zachová TizenTube nastavení včetně uživatelsky ovladatelného SponsorBlocku

Stabilní build zachovává původní YouTube / Cobalt vzhled. Experimentální TubeTV Blue UI není součástí v1.0.0.

## Jak dělat další verzi

Stabilní `patches/tubetv-stable-v1.js` nech jako nedotčený baseline v1.0.0. Pro další verzi vytvoř nový verzovaný soubor, například:

```text
patches/tubetv-v1.0.1.js
```

Pak sestav novou IPA ze stejného lokálního `Tube.tipa`:

```bash
python3 tools/build_tubetv.py Tube.tipa \
  --js patches/tubetv-v1.0.1.js \
  -o TubeTV-v1.0.1.ipa
```

Aktuální rezervovaná JS oblast má maximálně **2040 bajtů**. Pokud nová injekce tento limit překročí nebo se změní základní YouTube tvOS verze, nepoužívej staré offsety naslepo — vytvoř a samostatně ověř novou patch mapu.

Pokud se mění native patch, aktualizuj odpovídající mapu / `.hex` soubor a před vydáním porovnej nový build proti očekávaným hodnotám.

## Doporučený release workflow

1. Nech `tubetv-stable-v1.js` jako referenční zdroj v1.0.0.
2. Vytvoř nový verzovaný patch pro další release.
3. Proveď změny v `patches/` nebo builderu.
4. Vygeneruj IPA z lokálního `Tube.tipa`.
5. Nainstaluj a otestuj ji na Apple TV.
6. Po potvrzení funkčnosti aktualizuj README / release notes.
7. Vydej nový GitHub Release s novou IPA.

Tím zůstává v1.0.0 vždy reprodukovatelná a každá další verze má vlastní zdroj změn v `Masteru`.

## Podepisování a instalace

Builder vytvoří patched IPA, ale podpis pro konkrétní Apple TV se řeší samostatně použitou sideload/signing metodou. Certifikáty a provisioning profily se do repozitáře neukládají.

## Starý SwiftUI klient

Původní samostatný SwiftUI TubeTV klient už není aktivní implementace. Jeho zdroj zůstává v Git historii, například na commitu:

```text
f0669a85acb2150fe395ca7efe991a793220d245
```

Lze z něj kdykoli dohledat starší řešení, ale nové TubeTV verze se staví z aktuálního patchovacího základu v `Masteru` a z lokálně uloženého `Tube.tipa`.
