# diya Linux

**diya Linux** je specijalizovana Linux distribucija za audiofile.

To je MX Linux derivat razvijan od 2023. godine sa jednom konkretnom namenom: da računar bude stabilna, predvidljiva i pažljivo podešena platforma za reprodukciju muzike.

diya Linux nije zamišljen kao univerzalna Linux distribucija niti kao pokušaj da se napravi još jedan operativni sistem od nule. Osnovu čini MX Linux, dok su sistem, kernel, audio konfiguracija, boot okruženje i druga podešavanja prilagođeni potrebama audio reprodukcije.

Ceo projekat je nastao iz praktičnog rada sa stvarnim audio sistemom, a ne iz ideje da se što veći broj podešavanja proglasi "audiophile" podešavanjima.

---

## ISO preuzimanje

Gotov diya Linux Live ISO dostupan je na GitHub Releases:

[Preuzmi diya Linux v2.0 ISO](https://github.com/mikorist/diya-linux/releases/download/diya_linux_v2.0/diya-linux-v2.0.iso)

Trenutna verzija:

- Verzija: v2.0
- Datum: 24. novembar 2026.
- Veličina: 2.064.752.640 bajtova (1,92 GiB)
- MD5: `eaa55f95ab93f400a87dda7dac91ad94`
- SHA256: `71a5f27235827f8a1fd0e680d2acc59a176eda85986293814de3f28fb7e4e015`

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

Snapshot omogućava da se sačuva konkretno stanje sistema i da se ono kasnije ponovo obnovi. `setup_root.sh` preuzima baš ovaj tag, proverava SHA256 i raspakuje sadržaj u `root-mx25/`.

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

Pored modula za skladište i Live filesystem, u initrd se kopiraju i KMS moduli za fizičke grafičke adaptere:

- Intel: `i915` i `xe`
- AMD: `amdgpu` i `radeon`
- NVIDIA: `nouveau` (otvoreni drajver)

Uz njih se kopiraju odgovarajući direktorijumi firmware-a iz `root-mx25/lib/firmware/`. Ovo je važno zato što antiX Live initrd radi detekciju i učitavanje grafičkih modula pre prelaska u glavni root filesystem.

XFCE početni profil ne treba da sadrži zapamćen HDMI izlaz, EDID ili rezoluciju sa računara na kome se distro razvija. `customize_root.sh` uklanja takve monitor-specifične profile iz `/etc/skel`, kako bi XFCE otkrio priključeni ekran na ciljnom računaru.

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

Podrazumevani QEMU test koristi VirtIO grafički adapter. On proverava VirtIO putanju, ali ne predstavlja test fizičkih Intel, AMD ili NVIDIA kartica. Za dodatni generički VGA test može se promeniti adapter, na primer:

```bash
QEMU_VGA=std ./test_qemu.sh
```

Konačna provera fizičkih grafičkih kartica zahteva pokretanje ISO-a na stvarnom računaru sa odgovarajućim hardverom. NVIDIA podrška u Live sistemu koristi Nouveau i odgovarajući firmware. Vlasnički drajver se ne instalira unapred.

Za instalaciju vlasničkog NVIDIA drajvera koristi se MX alat `ddm-mx`, dostupan kroz MX meni kao **Nvidia driver installer**. Alat prepoznaje PCI ID grafičke kartice, bira odgovarajuću granu drajvera, instalira kernel modul preko DKMS-a i može da vrati sistem na Nouveau komandom `sudo ddm-mx -p nvidia`. Potrebna je internet veza.

DDM-u su potrebni kernel headeri koji se tačno poklapaju sa aktivnim kernelom. Zato se uz MX AHS Liquorix kernel instalira i odgovarajući `linux-headers-liquorix-amd64` metapaket. Stari kernel se uklanja iz build stabla kako bi kernel, moduli i headeri ostali usklađeni.

Podrazumevani cilj je praktična podrška za NVIDIA kartice koje prepoznaje aktuelni MX drajver iz serije 580. DDM sam proverava PCI ID i preporučuje odgovarajuću dostupnu granu. Provera njegove baze za PCI ID-jeve `10DE:1C03`, `10DE:2484` i `10DE:2684` vraća NVIDIA 580 kao preporučeni drajver. To je provera baze podržanih uređaja, ne fizički test tih kartica.

Nisu obećane sve istorijske NVIDIA kartice: za modele van podrške vlasničkog drajvera ostaje Nouveau, ukoliko ga konkretan GPU i njegov firmware podržavaju. DDM za instalaciju drajvera zahteva internet vezu. Uspešna instalacija i učitavanje vlasničkog modula proveravaju se tek na fizičkom računaru.

Proverena je i AMD Radeon RX 570 4 GB (PCI ID `1002:67DF`): kernel je mapira na `amdgpu`, a svih 21 Polaris 10 firmware fajlova koje modul navodi nalaze se i u `root-mx25/` i u Live initrd-u. Ovo je provera sadržaja slike, ne zamena za završni test pokretanja na fizičkoj RX 570 kartici.

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
GitHub Release v2.0
     |
     v
  diya-linux-v2.0.iso
     |
     v
USB / virtuelna mašina
     |
     v
diya Linux
```

Nisu potrebni Git, build alati niti QEMU.

### Želim da ponovim build

Potrebni su Git repozitorijum i sačuvani filesystem snapshot.

Snapshot nije deo Git repozitorijuma zato što je veliki. Čuva se zasebno kao GitHub Release asset. Za diya Linux v2.0 koristi se release [diya_linux_v2.0](https://github.com/mikorist/diya-linux/releases/tag/diya_linux_v2.0), u kome su snapshot i SHA256 kontrolna suma:

```text
diya-root-mx25.tar.zst
```

Posle kloniranja repozitorijuma `root-mx25/` još ne postoji. On se automatski obnavlja pomoću `setup_root.sh`.

```text
GitHub repozitorijum
        |
        | git clone
        v
    diya-linux/
        |
        | ./setup_root.sh
        |       |
        |       +-- preuzima snapshot
        |       +-- proverava SHA256
        |       +-- raspakuje root filesystem
        |
        v
    root-mx25/
        |
        | ./build.sh
        v
    diya.iso
```

Prvo se klonira repozitorijum:

```bash
git clone git@github.com:mikorist/diya-linux.git
cd diya-linux
```

Zatim se pokreće:

```bash
./setup_root.sh
```

`setup_root.sh` preuzima `diya-root-mx25.tar.zst` sa GitHub Release-a, proverava njegovu SHA256 kontrolnu sumu i raspakuje snapshot u `root-mx25/`.

Snapshot u Release-u već sadrži pripremljen root filesystem diya Linux v2.0. Za ponavljanje iste verzije, posle `./setup_root.sh` ne treba ponovo pokretati prilagođavanje paketa. Dovoljno je pripremiti Live kernel i napraviti ISO.

`customize_root.sh` je opciona skripta za slučaj kada se namerno menja postojeći snapshot ili dodaju paketi. Radi isključivo nad `root-mx25/`, ne nad sistemom na kome se build pokreće. Osvežava APT liste u ciljnom filesystemu i instalira:

- `kdeconnect` za povezivanje Android telefona i tableta sa računarom
- `vlc` za reprodukciju muzike i videa
- `mpv` kao dodatni lagani plejer

KDE Connect indikator se dodaje u XFCE autostart, tako da se pokreće pri prijavi na desktop. Audio izlaz se ne preusmerava automatski: VLC i MPV koriste izlaz koji je izabran u audio sistemu diya Linux-a.

Skripta osvežava i MX AHS firmware pakete za AMD, Intel i NVIDIA grafiku, kako bi firmware odgovarao kernelu koji se isporučuje u Live sistemu.

Za identičan build iz objavljenog v2.0 snapshot-a priprema se Live kernel i initrd, pa se pokreće build:

```bash
./update_kernel.sh
./build.sh
```

`update_kernel.sh` kopira kernel i priprema initrd sa modulima i firmware-om za fizičke Intel, AMD i NVIDIA grafičke adaptere. `build.sh` ne preuzima snapshot i ne obnavlja `root-mx25/`. Njegov zadatak je da od već pripremljenog filesystema napravi Live ISO.

Osnovni antiX initrd čuva se u repozitorijumu kao iso-work/antiX/initrd-base.gz. `update_kernel.sh` od njega pravi radni `initrd.gz` i kopira odgovarajući kernel iz `root-mx25/boot/`. Osnovni `initrd-base.gz` je samo šablon za build i izostavlja se iz gotovog ISO-a. Generisani `initrd.gz`, `vmlinuz` i njihove MD5 kontrolne sume ostaju lokalni build izlazi i ne šalju se u Git.

Za opciono testiranje napravljenog ISO-a:

```bash
./test_qemu.sh
```

Na taj način Git repozitorijum ostaje mali i sadrži build infrastrukturu, konfiguraciju, boot fajlove i dokumentaciju, dok se veliki filesystem snapshot čuva odvojeno.

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

Trenutna verzija je diya Linux v2.0, napravljena 24. novembra 2026.

Gotov ISO se trenutno distribuira preko GitHub Releases.

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
### PipeWire i WirePlumber

Audio podešavanja se dodaju kao konfiguracioni fragmenti, umesto kopiranja kompletnih konfiguracionih fajlova stare verzije PipeWire-a. Time se koriste podrazumevane vrednosti aktuelnog paketa, a diya dodaje samo ono što je zaista potrebno.

- Osnovni PipeWire takt: 48 kHz.
- Dozvoljene PCM frekvencije: 32, 44.1, 48, 88.2, 96, 176.4, 192, 352.8 i 384 kHz.
- USB ALSA uređajima dozvoljen je multirate rad, kada ga sam uređaj podržava.
- Resampler koristi kvalitet 10 kada je konverzija neophodna.
- USB DAC koristi standardni idle timeout od 5 sekundi, čime se izbegava nepotrebno često otvaranje uređaja, a ostavlja mogućnost promene frekvencije između reprodukcija.
- Provereni Amanero profil ostaje 2 kanala, S32_LE, period 512, 64 perioda i headroom 512.

Podešavanja su u `/etc/skel/.config/pipewire/pipewire.conf.d/20-audio-quality.conf` i `/etc/skel/.config/wireplumber/wireplumber.conf.d/51-audio-policy.conf`. WirePlumber 0.5 koristi nativni `wireplumber.conf` format; stari Lua fragment nije deo nove instalacije.
