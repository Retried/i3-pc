# Plan optymalizacji wydajności i3-pc

Stan analizy: 2026-10-15. Zakres tego etapu: porównanie propozycji z kodem,
przegląd eksperymentalnego patcha priorytetu 1 i plan dalszej walidacji.
W pierwotnym etapie nie wdrażano patcha ani pozostałych priorytetów.
Późniejszą implementację priorytetu 2 opisano w sekcji aktualizacji poniżej;
tabela porównawcza zachowuje stan bazowy sprzed tej zmiany.
Plan rozszerzono także o etapy W1–W4 dla Windows, procesorów AMD Ryzen i GPU
NVIDIA. Ich numeracja jest odrębna od dotychczasowych priorytetów renderera 1–7.

## Podstawa i znaczenie statusów

Current hardware scope (2026-10-16): build, launch and validation targets are
AMD CPUs with NVIDIA Vulkan GPUs only. Historical references below to checking
other GPU vendors do not add them to the current scope. Both benchmark PCs must
use this target hardware; see AGENTS.md and docs/BENCHMARK_PROTOCOL.md.

Przejrzano lokalny checkout podmodułu `runtime`, przypięty do commita
`81b6211695fe3d1dc1b7712d7e6dcdef2c908275`. `.gitmodules` wskazuje gałąź
`runtime`; checkout ma odłączony HEAD. Analiza dotyczy tego lokalnego kodu,
nie potwierdza zgodności z najnowszym zdalnym tipem gałęzi.

- **Wdrożone**: wskazany mechanizm istnieje w kodzie; nie oznacza to potwierdzonego zysku.
- **Częściowo wdrożone**: istnieją elementy propozycji, lecz pozostaje konkretny zakres pracy.
- **Eksperymentalne**: istnieje patch poza checkoutem, bez pełnej walidacji.
- **Wymaga pomiarów**: hipoteza o koszcie lub korzyści, a nie wynik benchmarku.

Wszystkie korzyści w poniższej tabeli są hipotezami. Dane z
[`BENCHMARK.md`](BENCHMARK.md) opisują wcześniejsze pomiary i nie dowodzą
skuteczności tego patcha ani nowych propozycji. Liczby i obserwacje zapisane
w komentarzach kodu również nie są nowym benchmarkiem wykonanym w ramach tej analizy.

## Priorytety po porównaniu z kodem

| Priorytet | Propozycja i stan | Dowody w aktualnym kodzie | Pozostały zakres i hipoteza korzyści | Trudność / ryzyko |
| --- | --- | --- | --- | --- |
| 1 | Cache bindingów i wysyłanie tylko zmienionych deskryptorów: **eksperymentalne; wymaga pomiarów** | `Pipeline::BindResources` w `vk_pipeline_common.cpp` wysyła cały niepusty zestaw push descriptors; ścieżka zwykłych descriptor sets wykonuje `Commit`, `updateDescriptorSets` i bind. `CommandStream::pushDescriptorSetKHR` kopiuje dane do workera bez porównania z poprzednimi wartościami. | Ocenić i zwalidować dostarczony patch eliminujący powtórne wysyłanie push descriptors. Nie jest to pełny cache przygotowania zasobów. Hipoteza: mniej pracy CPU przy podobnych draw callach, potencjalnie więcej FPS. | Średnia–wysoka: poprawność stanu Vulkan i unieważniania cache. |
| 2 | Przyrostowy pipeline i szybszy wybór wariantu shadera: **częściowo wdrożone; wymaga pomiarów** | `GetGraphicsPipeline` ma cache ostatniego klucza i pipeline'u oraz mapę pipeline'ów. Jednak najpierw wywołuje `RefreshGraphicsKey`, który zeruje i odbudowuje klucz. `GetProgram` ma cache programów, ale dla istniejącego programu odświeża dane i buduje specjalizację, a następnie liniowo szuka jej w `program->modules`. | Zmierzyć koszt odbudowy klucza, specjalizacji i wyszukiwania. Dopiero potem projektować aktualizację zależnych pól oraz indeks wariantów. Hipoteza: mniej pracy CPU na draw. | Średnia: kompletność zależności rejestrów, danych shadera i pamięci. |
| 3 | Rzadsze sprawdzanie GPU i grupowanie submitów: **częściowo wdrożone; wymaga pomiarów** | `SubmitPeriodically` w `vk_rasterizer.cpp` już grupuje pracę, domyślnie co 512 wywołań tego helpera (`SOTC_SUBMIT_EVERY`). `Draw` wywołuje `PopPendingOperations`; ta funkcja robi `work_semaphore.Refresh`. `SubmitExecution` również odświeża semafor. Istnieją ticki i kolejka odroczonych operacji. | Zmierzyć liczbę i czas odczytów timeline, submitów i oczekiwań. Rozważyć ograniczenie pollingu z zachowaniem terminowego wykonania callbacków i sygnałów dla gościa. Hipoteza: mniejszy narzut synchronizacji. | Średnia: opóźnienie readbacku, pacing i głodzenie GPU przy zbyt dużych batchach. |
| 4 | Usuwanie redundantnych komend przed workerem: **częściowo wdrożone; wymaga pomiarów** | `Rasterizer::Draw` ma `LastDraw`, maskę zmian i szybką ścieżkę ponownego użycia render state. Scheduler unieważnia śledzony dynamic state przy nowej sesji. `CommandStream::bindPipeline` nadal bezwarunkowo kolejkuje bind. | Zinwentaryzować emitowane bindy i dynamic state oraz istniejące filtry. Priorytet 1 już realizuje fragment tej propozycji dla push descriptors; nie liczyć jego efektu ponownie. Hipoteza: mniej kopiowania po stronie producenta i wywołań sterownika po stronie workera. | Niska–średnia; rośnie przy komendach zmieniających zależny stan. |
| 5 | Precyzyjne zależności readbacku: **częściowo wdrożone; wymaga pomiarów i walidacji poprawności** | `BufferCache::DownloadMemory` śledzi zmodyfikowane zakresy, ale kończy przez `scheduler.Finish`. `MirrorToGuest` ma asynchroniczne kopie, ticki, limit wyprzedzenia i porównywanie zmienionych słów; część zachowań jest warunkowana identyfikatorem gry i zmiennymi `I3_*`. `DeferLabel` wiąże część readbacku z sygnałem ukończenia. | Opisać zależności producent–kopia–CPU, aliasowanie, nadpisania CPU i remapowanie pamięci. Nie zastępować istniejących waitów bez dowodu równoważności. Hipoteza: stabilność i możliwość dalszego ograniczenia globalnych oczekiwań. | Wysoka: wyścigi, spóźnione wyniki i uszkodzenie pamięci gościa. |
| 6 | Pipeline'y przed pierwszym użyciem: **wdrożone dla zgodnego zapisanego cache; częściowo dla całej propozycji; wymaga pomiarów** | Konstruktor `PipelineCache` wywołuje `WarmUp`. `vk_pipeline_serialization.cpp` sprawdza profil i wersję danych, odtwarza graphics/compute pipelines z bazy. Brakujące pipeline'y nadal powstają w `GetGraphicsPipeline` / `GetComputePipeline` przy użyciu. | Oddzielnie mierzyć start z pustym i ciepłym cache, trafienia, kompilacje podczas gry oraz czas startu. Ewentualny prewarm nowych wariantów wymaga osobnego projektu. Hipoteza: mniej przycięć i lepsze 1% low. | Średnia–wysoka: zgodność cache, pamięć, czas uruchomienia i kompletność wariantów. |
| 7 | Grupowanie draw calli panoramy miasta: **brak potwierdzonego wdrożenia takiego grupowania; wymaga pomiarów i projektu** | `CommandStream` udostępnia komendy indirect, a rasterizer ma szybką ścieżkę kolejnych draw calli. To nie dowodzi łączenia odrębnych draw calli panoramy w jeden batch. | Najpierw ustalić, czy stan zasobów, indeksy, stałe i zależności pozwalają zachować semantykę. Implementacja musi być ogólna, bez wyjątków dla gry lub shadera zgodnie z `runtime/AGENTS.md`. Hipoteza: znaczna redukcja narzutu CPU, bez oszacowanego rozmiaru zysku. | Bardzo wysoka: kolejność, bariery, blending, query i dane per draw. |

Ścieżki plików Vulkan w tabeli odnoszą się do
`runtime/src/video_core/renderer_vulkan/`; BufferCache znajduje się w
`runtime/src/video_core/buffer_cache/buffer_cache.cpp`.

## Ocena patcha priorytetu 1

Plik wejściowy: `priority1-push-descriptor-cache.patch`, dostarczony osobno.
Zmienia `vk_command_stream.cpp`, `vk_command_stream.h`, `vk_scheduler.cpp`
i `vk_scheduler.h`. `git apply --check --directory=runtime` zakończył się
powodzeniem na opisanym checkoutcie. Jest to wyłącznie sprawdzenie dopasowania
patcha: patch nie został zastosowany, skompilowany ani uruchomiony.
Zgodnie z informacją autora nie przeszedł pełnego buildu emulatora ani testów w grze.

### Faktyczny zakres

- Dwa niezależne cache dla graphics i compute, dla setu 0, po 64 bindingi.
- Porównanie typu i istotnych wartości deskryptora: buffer/offset/range,
  image view/layout, sampler lub texel buffer view.
- Wsparcie tylko pojedynczych deskryptorów (`descriptorCount == 1`,
  `dstArrayElement == 0`), bez `pNext`, dla wymienionych w patchu typów.
- Filtrowanie przed kopiowaniem danych do workera; przy braku zmian pomijane
  jest całe wywołanie. Dotyczy też trybu bez workera.
- Niewspierane zapisy przechodzą dotychczasową ścieżką i unieważniają cache.
- Wyłączenie przez obecność `SHAD_DISABLE_PUSH_DESCRIPTOR_CACHE` w środowisku
  (również wartość `0` wyłącza cache).

Patch **nie** pomija przygotowania zasobów, wyznaczania pipeline'u,
push constants ani aktualizacji zwykłych descriptor sets. Nie redukuje
liczby draw calli. Nie realizuje pełnego zakresu priorytetu 1.

### Mocne strony i warunki poprawności

Unieważnianie obejmuje zmianę layoutu, zmianę target command buffera,
`BeginSession`, zwykły `bindDescriptorSets`, ogólny `Set` oraz dostęp przez
`Scheduler::CommandBuffer`. Reset w `BeginSession` jest potrzebny także wtedy,
gdy ponownie użyto tej samej wartości uchwytu command buffera. Zachowana jest
dotychczasowa kopia danych zapisu przed asynchronicznym odtworzeniem; cache
przechowuje wartości, a nie wskaźniki do tablic użytkownika.

Porównanie uchwytu layoutu jest konserwatywne dla zmiany layoutu: wymusza
ponowne wysłanie podanego zestawu nawet przy layoutach kompatybilnych.
To upraszcza poprawność kosztem możliwych nietrafień cache.

### Ryzyka i otwarte punkty przeglądu

1. **Obejścia cache i czas życia uchwytów.** `RawCommandBuffer()` nie
   unieważnia cache; obecne znalezione wywołania służą porównywaniu uchwytów.
   Trzeba zachować ten kontrakt i sprawdzić bezpośrednie operacje Vulkan oraz
   ewentualne przechowywanie uchwytu zwróconego przez `CommandBuffer()` ponad
   kolejne operacje streamu. Jednorazowe unieważnienie przy pobraniu uchwytu
   nie chroni przed późniejszym zapisem z pominięciem streamu. Recykling
   uchwytów zasobów/layoutów również wymaga zgodnego zarządzania czasem życia.
2. **Skuteczność unieważniania.** Ogólny `Set` i każde `CommandBuffer()`
   unieważniają oba cache, nawet dla operacji niezwiązanych z deskryptorami.
   To bezpieczna ostrożność, ale częste wywołania mogą ograniczyć trafienia.
   Potrzebne są liczniki przyczyn unieważnienia i długości serii trafień.
3. **Pokrycie.** Cały batch wypada z cache, jeśli choć jeden zapis nie spełnia
   warunków. Zmierzyć rzeczywisty rozkład typów, liczby bindingów i zapisów
   tablicowych; nie zakładać, że większość draw calli skorzysta.
4. **Koszt porównania.** Każdy kandydat jest najpierw sprawdzany, następnie
   porównywany; przy często zmieniających się zasobach dochodzi koszt CPU bez
   oszczędności wywołań. Brak danych o bilansie na docelowej scenie.
5. **Semantyka stanu.** Weryfikacja musi objąć częściowe aktualizacje bindingów,
   przełączanie graphics/compute, layoutów i zwykłych sets, helpery blit/tile/fault,
   ponowny początek nagrywania oraz fallback dla `pNext` i dużych batchy.
   Eliminacja zapisów nie zastępuje barier ani śledzenia zawartości zasobów.

Wniosek przeglądu statycznego: zakres odpowiada ograniczeniu ponownego
wysyłania push descriptors, a dopasowanie do źródeł jest potwierdzone.
Nie stwierdzono na tej podstawie dowodu gotowości do wdrożenia; nie ma też
potwierdzonego wyniku wydajności ani pełnej weryfikacji poprawności.
Patch pozostaje eksperymentalnym kandydatem do walidacji.

## Kolejność dalszych prac

1. Zachować bazowy commit i identyczną konfigurację; przygotować osobny build
   z patchem priorytetu 1. Wykonać pełny build emulatora i sprawdzić diagnostykę.
2. Zweryfikować poprawność z cache włączonym i wyłączonym, z workerem i bez
   (`SOTC_WORKER_RECORD=0`), w tym zmiany scen, efekty, compute, readback,
   długą rozgrywkę i ponowne użycie command bufferów. Użyć warstw walidacji
   Vulkan do sprawdzania poprawności; pomiary czasu wykonać osobno bez ich narzutu.
3. Zmierzyć priorytet 1 w powtarzalnym A/B. Dopiero wynik poprawności i kosztu
   CPU pozwoli zdecydować o jego przyjęciu lub poprawkach.
4. Dla priorytetów 2–4 zebrać profile i ustalić udział kosztu, uwzględniając
   już istniejące optymalizacje oraz nakładanie się 1 i 4. Nie wdrażać ich
   w ramach obecnego etapu.
5. Priorytet 5 poprzedzić modelem zależności i analizą poprawności. Dla 6
   najpierw zmierzyć istniejący warmup. Priorytet 7 pozostawić jako badanie
   wykonalności po ocenie prostszych optymalizacji.

## Protokół pomiarów i kryteria decyzji

- Stałe: commit, patch, build i kompilator, sprzęt, sterownik, rozdzielczość,
  ustawienia, limit FPS, zapis gry, kamera/trasa i czas próby. Odnotować wszystkie
  zmienne środowiskowe. Zimny i rozgrzany cache shaderów mierzyć oddzielnie.
- Powtórzyć każdą konfigurację przynajmniej trzy razy, przeplatając kolejność
  A/B. Uwzględnić ciężką panoramę, scenę z często zmienianymi zasobami oraz
  lekką scenę kontrolną; porównywać również obraz i stabilność.
- Raportować rozkład frametime, medianę, p95/p99, średnie FPS, 1% low oraz
  rozrzut prób. Zdefiniować sposób liczenia 1% low i nie mieszać metod.
- Dla patcha mierzyć czas CPU przygotowania/wysyłania deskryptorów, czas workera,
  liczbę kandydatów i zmienionych zapisów, pominięte wywołania, bajty kopiowane
  do kolejki, fallbacki i unieważnienia. Dodatkowo obserwować czas GPU,
  submity i oczekiwania, aby rozpoznać przesunięcie wąskiego gardła.
- Warunek przyjęcia: pełny build, brak wykrytych regresji poprawności i stabilności,
  powtarzalna korzyść ponad rozrzut pomiaru oraz brak istotnej regresji w scenach
  kontrolnych. Sam wzrost liczby trafień cache nie dowodzi wzrostu FPS.

Na tym etapie nie wykonano buildów, uruchomień gry ani benchmarków. Brak wyników
nie oznacza zerowej korzyści; oznacza, że wielkość i koszt efektu są nieznane.

## Aktualizacja: implementacja priorytetu 2 (2026-10-15)

Na osobne polecenie wdrożono w źródłach pierwszy zakres priorytetu 2:

- `PipelineCache::GraphicsState` przechowuje kopię rejestrów wpływających na
  część klucza opisującą stan renderowania. Ich porównanie obejmuje pełne
  wskazane pola, niezależnie od tego, jaką ścieżką zapisano rejestry.
  Przy niezmienionych wartościach pomijana jest ponowna konwersja formatów,
  swizzle i pozostałych pól tej części klucza.
- Osobno zachowano klucz przed uwzględnieniem shaderów i wynik maskowania
  render targetów. Ten drugi jest używany ponownie tylko przy niezmienionych
  rejestrach i masce MRT. Hashy etapów i formatów wejścia wierzchołków nie
  pobiera się ze starego wyniku: pozostają aktualne z bieżącego draw calla.
- `Program::FindPermutation` pamięta wynik poprzedniego wyszukania dla
  programów z wieloma wariantami. Sprawdza specjalizację i identyczną maskę
  obecności zasobów. Jest to istotne, ponieważ dotychczasowe dopasowanie
  specjalizacji ignoruje część zasobów nieobecnych w zapytaniu. Po zmianie
  zapytania pozostaje dotychczasowe wyszukiwanie pierwszego pasującego wariantu;
  dodanie lub wstawienie wariantu unieważnia wynik.
- Cache ostatniego graphics pipeline'u należy teraz do instancji
  `PipelineCache`, zamiast być globalny. Usunięcie pipeline'u przy podmianie
  shadera nadal unieważnia ten wskaźnik.

Zachowano odświeżanie parametrów shaderów, pamięci SRT, specjalizacji i
fetch shaderów dla każdego draw/dispatch. Nie oparto poprawności na samej masce
`change_mask_since_draw`, która nie opisuje wszystkich zmian pamięci gościa.
Nie zmieniono formatu cache na dysku ani reguł kompilacji wariantów.
Pełne przyrostowe śledzenie zależności shaderów pozostaje dalszą możliwością,
wymagającą osobnego projektu. Priorytetów 1 i 3–7 nie wdrażano.

Walidacja tej aktualizacji:

- `git diff --check` dla zmian podmodułu: bez błędów.
- Sprawdzenie składni i typów zmienionego `vk_pipeline_cache.cpp`: zakończone
  powodzeniem; następnie plik skompilowano także w pełnym buildzie.
- Pełny build emulatora Windows x64, `RelWithDebInfo`, Clang 19.1.5 i MSVC:
  zakończony powodzeniem, łącznie z linkowaniem `shadps4.exe` w
  `runtime/Build/priority2-x64/`. Lokalnie wskazano Pythona dla glslang,
  64-bitowy proces Clanga dla emulatora i fontów, definicje Windows oraz
  pełną ścieżkę do 64-bitowej biblioteki builtins. Były to dostosowania lokalnego
  buildu; plików konfiguracji projektu nie zmieniano. Dostępny toolchain różni
  się od Clanga 23 wskazanego w repozytoryjnym `build.bat`.
- Nie wykonano testów w grze ani benchmarków. Poprawność działania podczas
  rozgrywki, oszczędności CPU i wpływ na FPS nadal wymagają weryfikacji.

## Rozszerzenie planu: Windows / AMD CPU / NVIDIA GPU

Źródło wymagań: przekazany dokument „Optymalizacja i rozwój i3-pc — Windows /
AMD CPU / NVIDIA GPU”. Poniżej zapisano jego zakres jako propozycje dalszych
prac; polecenie uzupełnienia dokumentacji nie rozpoczyna ich implementacji.

### Środowisko i cele

- Windows 10/11 x86-64, procesory AMD Ryzen i karty NVIDIA obsługujące Vulkan.
  Samo wsparcie Vulkan nie potwierdza dostępności wszystkich funkcji wymaganych
  przez emulator; trzeba sprawdzić konkretny model i sterownik.
- Europejska wersja inFAMOUS Second Son: CUSA00004, aktualizacja v1.07.
- Dwa komputery o różnych konfiguracjach. Ich modele CPU/GPU, pamięć, system
  i sterowniki należy zapisać przed pomiarami; nie zakładać identycznego
  ograniczenia wydajności na obu maszynach.
- Cel: poprawa średniego FPS, 1% low i frametime, mniej przycięć oraz większa
  stabilność przy zachowaniu poprawnego obrazu. Są to kryteria przyszłej oceny,
  a nie potwierdzone efekty zmian.

Projekt bazuje na `SotC-project/i3-pc`, natomiast bieżącym repozytorium prac
jest fork `Retried/i3-pc`. Implementacja dotychczasowego priorytetu 2 została
opublikowana w commicie `9a719c45` na gałęzi `runtime`; commit `887e3e9c`
gałęzi `main` zawiera roadmapę oraz adres i wskaźnik podmodułu forka.
Zaliczony build tej zmiany nie stanowi testu działania na docelowych GPU NVIDIA.

### Lista nowych etapów i stan po krótkim przeglądzie

| Etap | Proponowane zmiany | Co już istnieje / pliki do wykorzystania | Stan i rezultat do weryfikacji |
| --- | --- | --- | --- |
| W1 — automatyzacja kompilacji i uruchamiania | Przenośny proces wykrywania narzędzi, budowania, uruchamiania i przygotowania paczki portable; opcjonalne LTO. | `build.bat` i `build-lto.bat` korzystają z presetów CMake, ale mają sztywne ścieżki do Visual Studio Enterprise i LLVM. `install.sh` również ma lokalne ścieżki. Istnieją `runtime/CMakePresets.json`, `runtime/cmake/CMakeWindowsPresets.json`, katalog `dist/` i instrukcje w `README.md`. | **Częściowo wdrożone**: istnieje proces budowania i wariant LTO. Automatyczne wykrywanie narzędzi oraz kompletność i przenośność paczki wymagają implementacji lub weryfikacji. Rezultat: powtarzalny build i uruchomienie tej samej paczki na drugim komputerze bez kompilacji. |
| W2 — kompatybilność i diagnostyka NVIDIA | Audyt wymaganych funkcji Vulkan, shaderów, synchronizacji i readbacku; uzupełnienie brakującej diagnostyki i uzasadnionych fallbacków. | `Instance::CollectDeviceParameters` w `vk_instance.cpp` już loguje producenta, model, sterownik, wersję Vulkan i dostępne rozszerzenia. `GetDriverVersionName` rozpoznaje format wersji NVIDIA; istnieje wykrywanie i włączanie rozszerzeń oraz wymagania dla funkcji. `vk_pipeline_cache.cpp` zawiera także wybory profilu zależne od sterownika. | **Diagnostyka podstawowa wdrożona; cały etap częściowo wdrożony i wymaga testów sprzętowych**. Nie powielać istniejących logów. Rezultat: odtwarzalne zgłoszenia błędów oraz potwierdzona poprawność na docelowych NVIDIA, bez regresji na pozostałych GPU. |
| W3 — automatyczne benchmarki i profilowanie | Ujednolicony zapis wyników i metadanych, porównanie A/B oraz wykrywanie regresji na obu komputerach. | `bench.sh` zapisuje CSV i liczy FPS oraz lows z frametime; ponawianie przy zajętym środowisku nie zastępuje niezależnych powtórzeń pomiaru. Istnieją `abtest.sh`, `abtest2.sh`, `cityprof.sh`, `tools/perfsample.ps1`, `tools/symprof.py`, sampler `SOTC_PROFILE` i zapis `bench_frametimes.txt` w sterowniku videoout. Skrypty nadal zawierają lokalne ścieżki. | **Częściowo wdrożone; wymaga rozszerzenia i pomiarów**. Rezultat: raporty A/B z pełnym pochodzeniem danych, cold/warm cache i rozrzutem 3–5 przebiegów każdej konfiguracji na każdej maszynie. |
| W4 — optymalizacja CPU i draw calli | Wybrać kosztowne operacje na podstawie profilu, ograniczać redundantne stany i lookupy, rozważać bezpieczny cache i batching. | Dotychczasowe priorytety 1–7 obejmują ten zakres. Istnieją `DrawStats`, szybkie ścieżki w `vk_rasterizer.cpp`, worker w `vk_command_stream.cpp`, mechanizmy synchronizacji i cache pipeline'ów. Priorytet 2 ma już implementację i zaliczony build, lecz nie ma wyników z gry. | **Częściowo wdrożone; skuteczność wymaga pomiarów**. W4 jest etapem nadrzędnym dla istniejącej listy, nie dodatkową kopią tych optymalizacji. Rezultat: powtarzalna poprawa względem baseline'u, zweryfikowana na obu komputerach bez regresji obrazu lub stabilności. |

### Konkretny zakres przyszłych zmian

**W1:** wykrywać Visual Studio Build Tools/MSVC, CMake, Ninja i LLVM;
wybierać 64-bitowy proces kompilatora i właściwy target. Weryfikować dostępność
Pythona i pozostałych zależności projektu oraz zgodność wersji narzędzi.
Ścieżki wyznaczać względem repozytorium, instalacji narzędzi lub jawnych
parametrów. Zachować opcję LTO po sprawdzeniu wsparcia kompilatora i linkera.
Zwracać czytelne komunikaty i kody błędów. Paczka portable powinna zawierać
potrzebne pliki wykonywalne, biblioteki i zasoby; określić wymagania środowiska
uruchomieniowego, konfigurację startową i sposób uruchomienia na drugim PC.
Nie dołączać danych gry ani prywatnej konfiguracji użytkownika.

**W2:** sprawdzić wymagane i opcjonalne funkcje oraz ich inicjalizację w
`vk_instance.cpp` i wykorzystanie przez pipeline'y, scheduler oraz buffer cache.
Przeanalizować kompilację shaderów, synchronizację i GPU→CPU readback, w tym
założenia zależne od producenta lub sterownika. Dopisywać diagnostykę tam,
gdzie obecne dane nie wystarczają; unikać logowania każdego draw calla.
Fallback wprowadzać wyłącznie dla potwierdzonego braku funkcji lub błędu,
z zachowaniem poprawności i porównaniem z innymi GPU. Nie traktować samej
obecności ścieżek NVIDIA jako dowodu zgodności całego renderera.

**W3:** rozszerzać istniejące skrypty zamiast tworzyć równoległy system od zera.
Zachowywać surowe czasy klatek i statystyki CPU/GPU dostępne w danej konfiguracji;
brakujące wartości oznaczać jako niedostępne. Raport CSV lub JSON powinien
zawierać identyfikatory commitów `main` i `runtime`, stan lokalnych zmian,
konfigurację buildu, sprzęt, system, sterownik, ustawienia emulatora, scenę,
czas pomiaru, zmienne środowiskowe oraz stan cache shaderów.
Automatyczne porównanie powinno uwzględniać średni FPS, 1% low, rozkład
frametime i rozrzut wyników; progi regresji ustalić po zebraniu baseline'u.
Cold cache i warm cache muszą stanowić osobne serie, każda po 3–5 przebiegów.

**W4:** profilować koszt tłumaczenia draw calli, przygotowania zasobów,
wyboru pipeline'u, deskryptorów, nagrywania komend i synchronizacji. Najpierw
ocenić już istniejące optymalizacje, w tym commit `9a719c45` i osobny patch
push descriptors. Nie sumować nakładających się przewidywanych korzyści.
Cache, batching i wielowątkowość wymagają analizy zależności i zachowania
semantyki renderowania. Nie wprowadzać agresywnej wielowątkowości przed
profilowaniem ani wyjątków dla konkretnej gry lub shadera.

### Kolejność, kryteria etapów i ręczna weryfikacja

Nowy cykl planować w kolejności **W1 → W2 → W3 → W4**. Nie zmienia to
historycznej numeracji priorytetów 1–7 ani statusu już zapisanej implementacji.
Przed rozpoczęciem W1 przygotować audyt struktury, dokumentacji, systemu
kompilacji, profilera i renderera oraz krótką listę zmian z plikami i funkcjami.
Powyższy przegląd jest punktem wyjścia, nie kompletnym audytem zgodności NVIDIA.

Przed każdą większą zmianą opisać problem, rozwiązanie, ryzyko regresji i sposób
weryfikacji. Wprowadzać małe, wydzielone zmiany, zachowywać CUSA00004 v1.07,
styl projektu oraz istniejące optymalizacje, dopóki pomiary nie uzasadnią ich
zastąpienia. W nowych skryptach i komentarzach kodu używać tekstu bez polskich
znaków. Sukces kompilacji nie oznacza poprawności gry, a wzrost FPS kosztem
obrazu lub stabilności nie spełnia kryteriów przyjęcia.

| Etap | Weryfikacja wymagająca uruchomienia / sprzętu | Warunek zamknięcia |
| --- | --- | --- |
| W1 | Zbudować projekt i wariant LTO, jeśli wspierany; utworzyć paczkę i uruchomić ją na drugim komputerze bez środowiska kompilacji. | Instrukcja budowania i pakowania, lista zależności oraz potwierdzony start i próba działania gry na drugim PC. |
| W2 | Zebrać logi obu konfiguracji, sprawdzić renderowanie, shadery, efekty, readback, zmiany scen i dłuższą rozgrywkę. Uruchomienia z walidacją Vulkan oddzielić od pomiarów wydajności; zakres kontroli innych GPU jawnie opisać. | Udokumentowana macierz sprzętu/sterowników, wyniki prób, brak wykrytych regresji w sprawdzonym zakresie i lista nieweryfikowanych konfiguracji. |
| W3 | Powtórzyć te same sceny i ustawienia 3–5 razy na każdym PC, osobno z zimnym i rozgrzanym cache; sprawdzić surowe dane i raport porównawczy. | Powtarzalny raport A/B, kompletne metadane i jawna metoda obliczania metryk oraz wykrywania regresji. |
| W4 | Porównać każdą optymalizację z baseline'em na obu PC; ocenić obraz, stabilność, FPS, lows i frametime. | Korzyść poparta pomiarami, z rozrzutem wyników i kontrolą regresji. Bez danych nie deklarować przyspieszenia. |

Po każdym etapie przedstawić zmienione pliki z uzasadnieniem, instrukcję
odtworzenia, wyniki wykonanych sprawdzeń, ograniczenia i ryzyka oraz propozycję
dalszych prac. Dla W1 dołączyć instrukcję kompilacji i paczki portable.
Jawnie wskazać próby wymagające dostępu do gry, docelowego GPU lub drugiego PC.
Nie rozpoczynać automatycznie kolejnego etapu; każdy powinien dać się osobno
sprawdzić i zatwierdzić.

Status tego rozszerzenia: **plan prac**. W ramach uzupełnienia dokumentacji
nie zmieniono skryptów ani renderera i nie wykonano nowych buildów, benchmarków
lub testów w grze na docelowych konfiguracjach.

## W1 implementation update (2026-10-16)

The W1 row above describes the original planning audit. The wrapper now uses
`tools/build-windows.ps1` for x64 tool discovery and separate normal/LTO builds,
and `tools/package-windows.ps1` for allowlisted ZIP packaging with build metadata,
hashes and dependency inspection. `install.sh` resolves paths from its checkout.
Current validation and usage are tracked in [W1_WINDOWS.md](W1_WINDOWS.md).
Second-PC launch remains required before closing W1. W2-W4 are not started by
this implementation; renderer priority 1 remains unapplied and no FPS improvement
is claimed.
