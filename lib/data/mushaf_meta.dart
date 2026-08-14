// GENERATED — do not hand-edit. Mushaf (Madani / King Fahd 604-page Hafs)
// structural metadata: page starts, juz starts, sajda ayat, and per-surah
// facts. Source: the `quran-meta` package's Hafs lists (MIT, (c) 2020
// Quran-Center) cross-checked against this repo's own assets/quran/quran_full.json
// — every surah's first global ayah id matches the bundled corpus exactly,
// so a global ayah index here is directly an index into StudioState.ayaat.
//
// Global ayah ids are 1-based (1 = الفاتحة:1 … 6236 = الناس:6); the bundled
// corpus list is 0-based, so index = globalAyahId - 1.

/// First global ayah id (1-based) of each of the mushaf's 604 pages.
/// `kPageStartAyahId[0]` is page 1.
const List<int> kPageStartAyahId = [
  1, 8, 13, 24, 32, 37, 45, 56, 65, 69, 77, 84,
  91, 96, 101, 109, 113, 120, 127, 134, 142, 149, 153, 161,
  171, 177, 184, 189, 194, 198, 204, 210, 218, 223, 227, 232,
  238, 241, 245, 253, 256, 260, 264, 267, 272, 277, 282, 289,
  290, 294, 303, 309, 316, 323, 331, 339, 346, 355, 364, 371,
  377, 385, 394, 402, 409, 415, 426, 434, 442, 447, 451, 459,
  467, 474, 480, 488, 494, 500, 505, 508, 513, 517, 520, 527,
  531, 538, 545, 553, 559, 568, 573, 580, 585, 588, 595, 599,
  607, 615, 621, 628, 634, 641, 648, 656, 664, 669, 672, 675,
  679, 683, 687, 693, 701, 706, 711, 715, 720, 727, 734, 740,
  746, 752, 759, 765, 773, 778, 783, 790, 798, 808, 817, 825,
  834, 842, 849, 858, 863, 871, 880, 884, 891, 900, 908, 914,
  921, 927, 932, 936, 941, 947, 955, 966, 977, 985, 992, 998,
  1006, 1012, 1022, 1028, 1036, 1042, 1050, 1059, 1075, 1085, 1092, 1098,
  1104, 1110, 1114, 1118, 1125, 1133, 1142, 1150, 1161, 1169, 1177, 1186,
  1194, 1201, 1206, 1213, 1222, 1230, 1236, 1242, 1249, 1256, 1262, 1267,
  1272, 1276, 1283, 1290, 1297, 1304, 1308, 1315, 1322, 1329, 1335, 1342,
  1347, 1353, 1358, 1365, 1371, 1379, 1385, 1390, 1398, 1407, 1418, 1426,
  1435, 1443, 1453, 1462, 1471, 1479, 1486, 1493, 1502, 1511, 1519, 1527,
  1536, 1545, 1555, 1562, 1571, 1582, 1591, 1601, 1611, 1619, 1627, 1634,
  1640, 1649, 1660, 1666, 1675, 1683, 1692, 1700, 1708, 1713, 1721, 1726,
  1736, 1742, 1750, 1756, 1761, 1769, 1775, 1784, 1793, 1803, 1818, 1834,
  1854, 1873, 1893, 1908, 1916, 1928, 1936, 1944, 1956, 1966, 1974, 1981,
  1989, 1995, 2004, 2012, 2020, 2030, 2037, 2047, 2057, 2068, 2079, 2088,
  2096, 2105, 2116, 2126, 2134, 2145, 2156, 2161, 2168, 2175, 2186, 2194,
  2202, 2215, 2224, 2238, 2251, 2262, 2276, 2289, 2302, 2315, 2327, 2346,
  2361, 2386, 2400, 2413, 2425, 2436, 2447, 2462, 2474, 2484, 2494, 2508,
  2519, 2528, 2541, 2556, 2565, 2574, 2585, 2596, 2601, 2611, 2619, 2626,
  2634, 2642, 2651, 2660, 2668, 2674, 2691, 2701, 2716, 2733, 2748, 2763,
  2778, 2792, 2802, 2812, 2819, 2823, 2828, 2835, 2845, 2850, 2853, 2858,
  2867, 2876, 2888, 2899, 2911, 2923, 2933, 2952, 2972, 2993, 3016, 3044,
  3069, 3092, 3116, 3139, 3160, 3173, 3182, 3195, 3204, 3215, 3223, 3236,
  3248, 3258, 3266, 3274, 3281, 3288, 3296, 3303, 3312, 3323, 3330, 3337,
  3347, 3355, 3364, 3371, 3379, 3386, 3393, 3404, 3415, 3425, 3434, 3442,
  3451, 3460, 3470, 3481, 3489, 3498, 3504, 3515, 3524, 3534, 3540, 3549,
  3556, 3564, 3569, 3577, 3584, 3588, 3596, 3607, 3614, 3621, 3629, 3638,
  3646, 3655, 3664, 3672, 3679, 3691, 3699, 3705, 3718, 3733, 3746, 3760,
  3776, 3789, 3813, 3840, 3865, 3891, 3915, 3942, 3971, 3987, 3997, 4013,
  4032, 4054, 4064, 4069, 4080, 4090, 4099, 4106, 4115, 4126, 4133, 4141,
  4150, 4159, 4167, 4174, 4183, 4192, 4200, 4211, 4219, 4230, 4239, 4248,
  4257, 4265, 4273, 4283, 4288, 4295, 4304, 4317, 4324, 4336, 4348, 4359,
  4373, 4386, 4399, 4415, 4433, 4454, 4474, 4487, 4496, 4506, 4516, 4525,
  4531, 4539, 4546, 4557, 4565, 4575, 4584, 4593, 4599, 4607, 4612, 4617,
  4624, 4631, 4646, 4666, 4682, 4706, 4727, 4750, 4767, 4785, 4811, 4829,
  4853, 4874, 4896, 4918, 4942, 4969, 4996, 5030, 5056, 5079, 5087, 5094,
  5100, 5105, 5111, 5116, 5126, 5130, 5136, 5143, 5151, 5156, 5162, 5169,
  5178, 5186, 5193, 5200, 5209, 5218, 5223, 5230, 5237, 5242, 5254, 5268,
  5287, 5314, 5332, 5358, 5386, 5415, 5430, 5448, 5461, 5476, 5495, 5513,
  5543, 5571, 5597, 5617, 5642, 5673, 5703, 5728, 5759, 5801, 5830, 5855,
  5883, 5910, 5932, 5964, 5994, 6017, 6044, 6073, 6099, 6126, 6138, 6156,
  6177, 6194, 6208, 6222,
];

/// First global ayah id (1-based) of each of the 30 ajzaa'.
const List<int> kJuzStartAyahId = [
  1, 149, 260, 386, 517, 641, 751, 900, 1042, 1201,
  1328, 1479, 1649, 1803, 2030, 2215, 2484, 2674, 2876, 3215,
  3386, 3564, 3733, 4090, 4265, 4511, 4706, 5105, 5242, 5673,
];

/// Global ayah ids carrying a prostration (سجدة تلاوة).
const List<int> kSajdaAyahIds = [
  1160, 1722, 1951, 2138, 2308, 2613, 2672, 2915,
  3185, 3518, 3994, 4256, 4846, 5905, 6125,
];

const int kTotalAyat = 6236;
const int kTotalPages = 604;

class SurahMeta {
  /// 1-based surah number.
  final int num;
  /// Global ayah id (1-based) of this surah's first ayah.
  final int firstAyahId;
  final int ayahCount;
  /// Order of revelation (1 = العلق).
  final int revelationOrder;
  final int rukuCount;
  final bool meccan;
  /// Latin transliteration of the Arabic name, e.g. 'Al-Fatihah'.
  final String transliteration;
  /// English meaning of the name, e.g. 'The Opener'.
  final String englishName;
  const SurahMeta(this.num, this.firstAyahId, this.ayahCount,
      this.revelationOrder, this.rukuCount, this.meccan, this.transliteration,
      this.englishName);

  int get lastAyahId => firstAyahId + ayahCount - 1;
}

const List<SurahMeta> kSurahMeta = [
  SurahMeta(1, 1, 7, 5, 1, true, 'Al-Fatihah', 'The Opener'),
  SurahMeta(2, 8, 286, 87, 40, false, 'Al-Baqarah', 'The Cow'),
  SurahMeta(3, 294, 200, 89, 20, false, 'Ali \'Imran', 'Family of Imran'),
  SurahMeta(4, 494, 176, 92, 24, false, 'An-Nisa', 'The Women'),
  SurahMeta(5, 670, 120, 112, 16, false, 'Al-Ma\'idah', 'The Table Spread'),
  SurahMeta(6, 790, 165, 55, 20, true, 'Al-An\'am', 'The Cattle'),
  SurahMeta(7, 955, 206, 39, 24, true, 'Al-A\'raf', 'The Heights'),
  SurahMeta(8, 1161, 75, 88, 10, false, 'Al-Anfal', 'The Spoils of War'),
  SurahMeta(9, 1236, 129, 113, 16, false, 'At-Tawbah', 'The Repentance'),
  SurahMeta(10, 1365, 109, 51, 11, true, 'Yunus', 'Jonah'),
  SurahMeta(11, 1474, 123, 52, 10, true, 'Hud', 'Hud'),
  SurahMeta(12, 1597, 111, 53, 12, true, 'Yusuf', 'Joseph'),
  SurahMeta(13, 1708, 43, 96, 6, false, 'Ar-Ra\'d', 'The Thunder'),
  SurahMeta(14, 1751, 52, 72, 7, true, 'Ibrahim', 'Abraham'),
  SurahMeta(15, 1803, 99, 54, 6, true, 'Al-Hijr', 'The Rocky Tract'),
  SurahMeta(16, 1902, 128, 70, 16, true, 'An-Nahl', 'The Bee'),
  SurahMeta(17, 2030, 111, 50, 12, true, 'Al-Isra', 'The Night Journey'),
  SurahMeta(18, 2141, 110, 69, 12, true, 'Al-Kahf', 'The Cave'),
  SurahMeta(19, 2251, 98, 44, 6, true, 'Maryam', 'Mary'),
  SurahMeta(20, 2349, 135, 45, 8, true, 'Taha', 'Ta-Ha'),
  SurahMeta(21, 2484, 112, 73, 7, true, 'Al-Anbya', 'The Prophets'),
  SurahMeta(22, 2596, 78, 103, 10, false, 'Al-Hajj', 'The Pilgrimage'),
  SurahMeta(23, 2674, 118, 74, 6, true, 'Al-Mu\'minun', 'The Believers'),
  SurahMeta(24, 2792, 64, 102, 9, false, 'An-Nur', 'The Light'),
  SurahMeta(25, 2856, 77, 42, 6, true, 'Al-Furqan', 'The Criterion'),
  SurahMeta(26, 2933, 227, 47, 11, true, 'Ash-Shu\'ara', 'The Poets'),
  SurahMeta(27, 3160, 93, 48, 7, true, 'An-Naml', 'The Ant'),
  SurahMeta(28, 3253, 88, 49, 8, true, 'Al-Qasas', 'The Stories'),
  SurahMeta(29, 3341, 69, 85, 7, true, 'Al-\'Ankabut', 'The Spider'),
  SurahMeta(30, 3410, 60, 84, 6, true, 'Ar-Rum', 'The Romans'),
  SurahMeta(31, 3470, 34, 57, 3, true, 'Luqman', 'Luqman'),
  SurahMeta(32, 3504, 30, 75, 3, true, 'As-Sajdah', 'The Prostration'),
  SurahMeta(33, 3534, 73, 90, 9, false, 'Al-Ahzab', 'The Combined Forces'),
  SurahMeta(34, 3607, 54, 58, 6, true, 'Saba', 'Sheba'),
  SurahMeta(35, 3661, 45, 43, 5, true, 'Fatir', 'Originator'),
  SurahMeta(36, 3706, 83, 41, 5, true, 'Ya-Sin', 'Ya Sin'),
  SurahMeta(37, 3789, 182, 56, 5, true, 'As-Saffat', 'Those who set the Ranks'),
  SurahMeta(38, 3971, 88, 38, 5, true, 'Sad', 'The Letter "Saad"'),
  SurahMeta(39, 4059, 75, 59, 8, true, 'Az-Zumar', 'The Troops'),
  SurahMeta(40, 4134, 85, 60, 9, true, 'Ghafir', 'The Forgiver'),
  SurahMeta(41, 4219, 54, 61, 6, true, 'Fussilat', 'Explained in Detail'),
  SurahMeta(42, 4273, 53, 62, 5, true, 'Ash-Shuraa', 'The Consultation'),
  SurahMeta(43, 4326, 89, 63, 7, true, 'Az-Zukhruf', 'The Ornaments of Gold'),
  SurahMeta(44, 4415, 59, 64, 3, true, 'Ad-Dukhan', 'The Smoke'),
  SurahMeta(45, 4474, 37, 65, 4, true, 'Al-Jathiyah', 'The Crouching'),
  SurahMeta(46, 4511, 35, 66, 4, true, 'Al-Ahqaf', 'The Wind-Curved Sandhills'),
  SurahMeta(47, 4546, 38, 95, 4, false, 'Muhammad', 'Muhammad'),
  SurahMeta(48, 4584, 29, 111, 4, false, 'Al-Fath', 'The Victory'),
  SurahMeta(49, 4613, 18, 106, 2, false, 'Al-Hujurat', 'The Rooms'),
  SurahMeta(50, 4631, 45, 34, 3, true, 'Qaf', 'The Letter "Qaf"'),
  SurahMeta(51, 4676, 60, 67, 3, true, 'Adh-Dhariyat', 'The Winnowing Winds'),
  SurahMeta(52, 4736, 49, 76, 2, true, 'At-Tur', 'The Mount'),
  SurahMeta(53, 4785, 62, 23, 3, true, 'An-Najm', 'The Star'),
  SurahMeta(54, 4847, 55, 37, 3, true, 'Al-Qamar', 'The Moon'),
  SurahMeta(55, 4902, 78, 97, 3, false, 'Ar-Rahman', 'The Beneficent'),
  SurahMeta(56, 4980, 96, 46, 3, true, 'Al-Waqi\'ah', 'The Inevitable'),
  SurahMeta(57, 5076, 29, 94, 4, false, 'Al-Hadid', 'The Iron'),
  SurahMeta(58, 5105, 22, 105, 3, false, 'Al-Mujadila', 'The Pleading Woman'),
  SurahMeta(59, 5127, 24, 101, 3, false, 'Al-Hashr', 'The Exile'),
  SurahMeta(60, 5151, 13, 91, 2, false, 'Al-Mumtahanah', 'She that is to be examined'),
  SurahMeta(61, 5164, 14, 109, 2, false, 'As-Saf', 'The Ranks'),
  SurahMeta(62, 5178, 11, 110, 2, false, 'Al-Jumu\'ah', 'The Congregation, Friday'),
  SurahMeta(63, 5189, 11, 104, 2, false, 'Al-Munafiqun', 'The Hypocrites'),
  SurahMeta(64, 5200, 18, 108, 2, false, 'At-Taghabun', 'The Mutual Disillusion'),
  SurahMeta(65, 5218, 12, 99, 2, false, 'At-Talaq', 'The Divorce'),
  SurahMeta(66, 5230, 12, 107, 2, false, 'At-Tahrim', 'The Prohibition'),
  SurahMeta(67, 5242, 30, 77, 2, true, 'Al-Mulk', 'The Sovereignty'),
  SurahMeta(68, 5272, 52, 2, 2, true, 'Al-Qalam', 'The Pen'),
  SurahMeta(69, 5324, 52, 78, 2, true, 'Al-Haqqah', 'The Reality'),
  SurahMeta(70, 5376, 44, 79, 2, true, 'Al-Ma\'arij', 'The Ascending Stairways'),
  SurahMeta(71, 5420, 28, 71, 2, true, 'Nuh', 'Noah'),
  SurahMeta(72, 5448, 28, 40, 2, true, 'Al-Jinn', 'The Jinn'),
  SurahMeta(73, 5476, 20, 3, 2, true, 'Al-Muzzammil', 'The Enshrouded One'),
  SurahMeta(74, 5496, 56, 4, 2, true, 'Al-Muddaththir', 'The Cloaked One'),
  SurahMeta(75, 5552, 40, 31, 2, true, 'Al-Qiyamah', 'The Resurrection'),
  SurahMeta(76, 5592, 31, 98, 2, false, 'Al-Insan', 'The Man'),
  SurahMeta(77, 5623, 50, 33, 2, true, 'Al-Mursalat', 'The Emissaries'),
  SurahMeta(78, 5673, 40, 80, 2, true, 'An-Naba', 'The Tidings'),
  SurahMeta(79, 5713, 46, 81, 2, true, 'An-Nazi\'at', 'Those who drag forth'),
  SurahMeta(80, 5759, 42, 24, 1, true, '\'Abasa', 'He Frowned'),
  SurahMeta(81, 5801, 29, 7, 1, true, 'At-Takwir', 'The Overthrowing'),
  SurahMeta(82, 5830, 19, 82, 1, true, 'Al-Infitar', 'The Cleaving'),
  SurahMeta(83, 5849, 36, 86, 1, true, 'Al-Mutaffifin', 'The Defrauding'),
  SurahMeta(84, 5885, 25, 83, 1, true, 'Al-Inshiqaq', 'The Sundering'),
  SurahMeta(85, 5910, 22, 27, 1, true, 'Al-Buruj', 'The Mansions of the Stars'),
  SurahMeta(86, 5932, 17, 36, 1, true, 'At-Tariq', 'The Nightcommer'),
  SurahMeta(87, 5949, 19, 8, 1, true, 'Al-A\'la', 'The Most High'),
  SurahMeta(88, 5968, 26, 68, 1, true, 'Al-Ghashiyah', 'The Overwhelming'),
  SurahMeta(89, 5994, 30, 10, 1, true, 'Al-Fajr', 'The Dawn'),
  SurahMeta(90, 6024, 20, 35, 1, true, 'Al-Balad', 'The City'),
  SurahMeta(91, 6044, 15, 26, 1, true, 'Ash-Shams', 'The Sun'),
  SurahMeta(92, 6059, 21, 9, 1, true, 'Al-Layl', 'The Night'),
  SurahMeta(93, 6080, 11, 11, 1, true, 'Ad-Duhaa', 'The Morning Hours'),
  SurahMeta(94, 6091, 8, 12, 1, true, 'Ash-Sharh', 'The Relief'),
  SurahMeta(95, 6099, 8, 28, 1, true, 'At-Tin', 'The Fig'),
  SurahMeta(96, 6107, 19, 1, 1, true, 'Al-\'Alaq', 'The Clot'),
  SurahMeta(97, 6126, 5, 25, 1, true, 'Al-Qadr', 'The Power'),
  SurahMeta(98, 6131, 8, 100, 1, false, 'Al-Bayyinah', 'The Clear Proof'),
  SurahMeta(99, 6139, 8, 93, 1, false, 'Az-Zalzalah', 'The Earthquake'),
  SurahMeta(100, 6147, 11, 14, 1, true, 'Al-\'Adiyat', 'The Courser'),
  SurahMeta(101, 6158, 11, 30, 1, true, 'Al-Qari\'ah', 'The Calamity'),
  SurahMeta(102, 6169, 8, 16, 1, true, 'At-Takathur', 'The Rivalry in world increase'),
  SurahMeta(103, 6177, 3, 13, 1, true, 'Al-\'Asr', 'The Declining Day'),
  SurahMeta(104, 6180, 9, 32, 1, true, 'Al-Humazah', 'The Traducer'),
  SurahMeta(105, 6189, 5, 19, 1, true, 'Al-Fil', 'The Elephant'),
  SurahMeta(106, 6194, 4, 29, 1, true, 'Quraysh', 'Quraysh'),
  SurahMeta(107, 6198, 7, 17, 1, true, 'Al-Ma\'un', 'The Small kindnesses'),
  SurahMeta(108, 6205, 3, 15, 1, true, 'Al-Kawthar', 'The Abundance'),
  SurahMeta(109, 6208, 6, 18, 1, true, 'Al-Kafirun', 'The Disbelievers'),
  SurahMeta(110, 6214, 3, 114, 1, false, 'An-Nasr', 'The Divine Support'),
  SurahMeta(111, 6217, 5, 6, 1, true, 'Al-Masad', 'The Palm Fiber'),
  SurahMeta(112, 6222, 4, 22, 1, true, 'Al-Ikhlas', 'The Sincerity'),
  SurahMeta(113, 6226, 5, 20, 1, true, 'Al-Falaq', 'The Daybreak'),
  SurahMeta(114, 6231, 6, 21, 1, true, 'An-Nas', 'Mankind'),
];

/// The 1-based mushaf page a global ayah id falls on. Binary search over
/// [kPageStartAyahId] — O(log 604), safe to call per frame.
int pageOfAyahId(int ayahId) {
  var lo = 0, hi = kPageStartAyahId.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (kPageStartAyahId[mid] <= ayahId) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo + 1;
}

/// Inclusive global-ayah-id range `(first, last)` printed on [page] (1..604).
(int, int) ayahRangeOfPage(int page) {
  final p = page.clamp(1, kTotalPages);
  final first = kPageStartAyahId[p - 1];
  final last =
      p >= kTotalPages ? kTotalAyat : kPageStartAyahId[p] - 1;
  return (first, last);
}

/// The 1-based juz a global ayah id belongs to.
int juzOfAyahId(int ayahId) {
  var lo = 0, hi = kJuzStartAyahId.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (kJuzStartAyahId[mid] <= ayahId) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return lo + 1;
}

/// Global ayah id (1-based) for a surah/ayah pair, or -1 when out of range.
int globalAyahId(int surahNum, int ayahNum) {
  if (surahNum < 1 || surahNum > 114) return -1;
  final m = kSurahMeta[surahNum - 1];
  if (ayahNum < 1 || ayahNum > m.ayahCount) return -1;
  return m.firstAyahId + ayahNum - 1;
}

bool hasSajda(int ayahId) => kSajdaAyahIds.contains(ayahId);
