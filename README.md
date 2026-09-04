# diya Linux

**diya Linux** je specijalizovana Linux distribucija za audiofile.

To je MX Linux derivat razvijan od 2023. godine sa jednom konkretnom namenom: da računar bude stabilna, predvidljiva i pažljivo podešena platforma za reprodukciju muzike.

diya Linux nije zamišljen kao univerzalna Linux distribucija niti kao pokušaj da se napravi još jedan operativni sistem od nule. Osnovu čini MX Linux, dok su sistem, kernel, audio konfiguracija, boot okruženje i druga podešavanja prilagođeni potrebama audio reprodukcije.

Ceo projekat je nastao iz praktičnog rada sa stvarnim audio sistemom, a ne iz ideje da se što veći broj podešavanja proglasi "audiophile" podešavanjima.

---

## ISO preuzimanje

Gotov diya Linux Live ISO dostupan je na Google Drive-u:

[Preuzmi diya Linux ISO](https://drive.google.com/file/d/14fCpKDDwaYW9FMTdBL4Veb6XSttrpHS-/view?usp=share_link)

Trenutna verzija:

- Datum: 4. septembar 2026.
- Veličina: približno 1,74 GB
- MD5: `7cb105456d92eea7a856a002bd948dfa`

Ako želite samo da koristite diya Linux, potrebno je samo preuzeti ISO.

GitHub repozitorijum nije namenjen tome da korisnik ručno sastavlja sistem. On čuva build proces, konfiguraciju i razvoj projekta.

---

## Audiofilski Linux

diya Linux je napravljen sa idejom da audio računar treba da radi svoj posao bez nepotrebnog mešanja u audio reprodukciju.

Zato se pažnja ne završava na izboru audio servera ili instalaciji nekoliko audio paketa.

Posmatra se ceo sistem:

- Linux kernel
- kernel moduli
- initrd
- USB audio
- ALSA
- PipeWire
- realtime podešavanja
- IRQ prioriteti
- memorijsko ponašanje
- USB kontroleri
- boot konfiguracija
- stabilnost Live sistema

Posebna pažnja posvećena je USB audio reprodukciji, uključujući rad sa uređajima kao što je Amanero Combo384.

U testiranju su korišćene konfiguracije koje uključuju:

- USB High-Speed
- `snd-usb-audio`
- 2 kanala
- 48 kHz
- `S32_LE`
- period 512
- buffer 32768
- USB feedback endpoint
- bez implicitnog feedback-a

Ove vrednosti nisu predstavljene kao univerzalna "magična" podešavanja za svaki sistem.

Poenta projekta je upravo suprotna: svaka promena treba da ima razlog, a njen efekat treba proveriti na stvarnom sistemu.

---

## Kako je diya Linux nastao

diya Linux se ne gradi od nule.

Postoji pripremljen filesystem koji predstavlja konkretno stanje diya Linux sistema. Build proces od njega pravi Live sistem zajedno sa kernelom, initrd-om i boot okruženjem.

Osnovna struktura projekta je:

```text
MX-25.2-AHS-diya/
├── build.sh
├── update_kernel.sh
├── test_qemu.sh
├── mx-isohybrid-mbr.bin
├── iso-work/
└── root-mx25/
```

`root-mx25/` je pripremljeni root filesystem iz kojeg se generiše Live sistem.

Veliki filesystem snapshot nije deo Git repozitorijuma. Čuva se zasebno kao kompresovani backup:

```text
diya-root-mx25.tar.zst
```

Snapshot omogućava da se sačuva konkretno stanje sistema i da se ono kasnije ponovo obnovi.

---

## Build sistem

Glavna skripta za izgradnju ISO-a je:

```text
build.sh
```

Ona automatizuje kompletan proces:

1. proveru strukture projekta
2. proveru boot fajlova
3. proveru staging direktorijuma
4. pravljenje SquashFS filesystema
5. kompresiju sistema
6. ažuriranje `linuxfs`
7. generisanje kontrolnih suma
8. ažuriranje informacija o verziji
9. pravljenje bootabilnog ISO-a pomoću `xorriso`
10. generisanje MD5 sume gotovog ISO-a

Filesystem se trenutno pravi kao SquashFS sa XZ kompresijom.

Cilj build sistema je da proces bude ponovljiv i proverljiv, a ne da svaki novi ISO zavisi od ručnog kopiranja fajlova i prethodnog sećanja šta je poslednji put urađeno.

---

## Kernel i initrd

Kernel i initrd priprema:

```text
update_kernel.sh
```

Skripta pronalazi kernel u `root-mx25/boot/`, proverava odgovarajuće module i priprema kernel i initrd koji će se koristiti u Live sistemu.

Posebno se proveravaju moduli potrebni za pokretanje Live sistema:

```text
overlay
squashfs
loop
isofs
```

Prethodne verzije se čuvaju kao backup kako bi bilo moguće vratiti prethodno stanje.

---

## Testiranje u QEMU

Za proveru napravljenog ISO-a postoji:

```text
test_qemu.sh
```

QEMU nije deo diya Linux sistema i nije potreban za njegovo normalno korišćenje.

Služi isključivo za testiranje da li se napravljeni ISO pravilno podiže u virtuelnoj mašini.

Ako QEMU nije instaliran, skripta može da instalira potrebne pakete.

---

## Šta je potrebno za ponavljanje builda?

Za korišćenje gotovog diya Linux ISO-a nije potrebno instalirati build alate.

Za ponavljanje builda potreban je Linux sistem sa standardnim alatima koje build skripte koriste:

```text
bash
coreutils
tar
zstd
squashfs-tools
xorriso
```

Potrebne su i administratorske privilegije (`sudo`).

Na Debian/MX Linux sistemu osnovni alati mogu se instalirati pomoću:

```bash
sudo apt install bash coreutils tar zstd squashfs-tools xorriso
```

Za opciono QEMU testiranje:

```bash
sudo apt install qemu-system-x86 qemu-utils qemu-system-gui
```

Za ponovnu izgradnju potreban je i odgovarajući `root-mx25` filesystem snapshot.

---

## Korišćenje ili ponavljanje builda

Postoje dva potpuno različita načina korišćenja ovog projekta.

### Samo želim diya Linux

Preuzme se gotov ISO:

```text
Google Drive
     |
     v
  diya.iso
     |
     v
USB / virtuelna mašina
     |
     v
diya Linux
```

Nisu potrebni Git, build alati niti QEMU.

### Želim da ponovim build

Potrebni su Git repozitorijum i sačuvani filesystem snapshot:

```text
GitHub repozitorijum
        +
root filesystem snapshot
        |
        v
    build.sh
        |
        v
    diya.iso
```

GitHub sadrži build infrastrukturu.

Snapshot `diya-root-mx25.tar.zst` čuva konkretno stanje root filesystema iz kojeg se može obnoviti `root-mx25/`.

---

## Princip razvoja

Razvoj diya Linux-a zasniva se na jednostavnom principu:

```text
stanje
  ↓
hipoteza
  ↓
test
  ↓
rezultat
  ↓
odluka
```

Promena se ne uvodi samo zato što zvuči dobro ili izgleda dobro u konfiguracionom fajlu.

Ako promena utiče na kernel, USB, audio stack, realtime ponašanje ili boot proces, prvo se proverava šta se stvarno promenilo.

Tek nakon testa odlučuje se da li promena ostaje.

---

## Audio sistem

Posebna pažnja posvećena je odnosu između Linux sistema i stvarnog audio hardvera.

Kod USB audio uređaja posmatraju se:

- USB režim rada
- kernel driver
- ALSA ponašanje
- audio server
- feedback mehanizam
- period i buffer
- realtime scheduling
- IRQ ponašanje
- opterećenje sistema

Cilj nije da se napravi konfiguracija koja samo izgleda impresivno.

Cilj je sistem koji se ponaša predvidljivo kada reprodukcija zaista počne.

---

## Status projekta

diya Linux je aktivan projekat.

Trenutni build sistem omogućava da se iz pripremljenog sistema ponovljivo napravi kompletan Live ISO.

Trenutna verzija odgovara ISO-u objavljenom 4. septembra 2026.

Gotov ISO se trenutno distribuira preko Google Drive-a.

GitHub služi za:

- build skripte
- konfiguraciju
- boot fajlove
- razvoj
- dokumentaciju
- backup projekta

---

## Poreklo i licence

diya Linux je derivat MX Linux-a.

Koristi komponente i softver iz Debian i MX Linux ekosistema, zajedno sa sopstvenim konfiguracijama, skriptama i sistemskim izmenama.

Pojedinačne komponente zadržavaju svoje originalne licence.

Ovaj repozitorijum prvenstveno čuva specifičan diya Linux build proces i konfiguraciju sistema.

---

## Ukratko

**diya Linux je Linux napravljen za audiofile.**

Ne pokušava da bude distribucija za svakoga.

Napravljen je za računar kojem je osnovni posao reprodukcija muzike i oko kojeg se ostatak sistema podešava tako da taj posao obavlja stabilno i predvidljivo.

ISO je namenjen korisniku.

GitHub je namenjen procesu.

Filesystem snapshot čuva konkretno stanje sistema.

A build skripte povezuju sve to u ponovljiv proces.