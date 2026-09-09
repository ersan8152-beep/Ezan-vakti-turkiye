
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_device_compass/flutter_device_compass.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const green = Color(0xFF087A52);
const darkGreen = Color(0xFF003F35);
const gold = Color(0xFFFFD66B);
const cream = Color(0xFFF7F1E5);

const provinces = [
  'Adana','Adıyaman','Afyonkarahisar','Ağrı','Aksaray','Amasya','Ankara','Antalya',
  'Ardahan','Artvin','Aydın','Balıkesir','Bartın','Batman','Bayburt','Bilecik',
  'Bingöl','Bitlis','Bolu','Burdur','Bursa','Çanakkale','Çankırı','Çorum',
  'Denizli','Diyarbakır','Düzce','Edirne','Elazığ','Erzincan','Erzurum','Eskişehir',
  'Gaziantep','Giresun','Gümüşhane','Hakkari','Hatay','Iğdır','Isparta','İstanbul',
  'İzmir','Kahramanmaraş','Karabük','Karaman','Kars','Kastamonu','Kayseri','Kilis',
  'Kırıkkale','Kırklareli','Kırşehir','Kocaeli','Konya','Kütahya','Malatya','Manisa',
  'Mardin','Mersin','Muğla','Muş','Nevşehir','Niğde','Ordu','Osmaniye','Rize',
  'Sakarya','Samsun','Siirt','Sinop','Sivas','Şanlıurfa','Şırnak','Tekirdağ',
  'Tokat','Trabzon','Tunceli','Uşak','Van','Yalova','Yozgat','Zonguldak'
];

const prayerNames = ['İmsak','Güneş','Öğle','İkindi','Akşam','Yatsı'];
const apiNames = ['Imsak','Sunrise','Dhuhr','Asr','Maghrib','Isha'];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  runApp(const EzanVaktiApp());
}

class EzanVaktiApp extends StatelessWidget {
  const EzanVaktiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Ezan Vakti Türkiye',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: cream,
      colorScheme: ColorScheme.fromSeed(seedColor: green),
      fontFamily: 'Arial',
    ),
    home: const AppShell(),
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;
  String city = 'Düzce';
  String district = 'Merkez';
  Map<String,String> times = {};
  bool loading = true;
  bool notificationsEnabled = false;
  final notifier = FlutterLocalNotificationsPlugin();
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    _initNotifications();
    _restore();
    ticker = Timer.periodic(const Duration(seconds:1), (_) { if (mounted) setState((){}); });
  }

  @override
  void dispose() { ticker?.cancel(); super.dispose(); }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await notifier.initialize(const InitializationSettings(android:android, iOS:ios));
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    city = p.getString('city') ?? 'Düzce';
    district = p.getString('district') ?? 'Merkez';
    notificationsEnabled = p.getBool('notifications') ?? false;
    await loadTimes();
  }

  Future<void> loadTimes() async {
    setState(() => loading = true);
    try {
      final u = Uri.parse(
        'https://api.aladhan.com/v1/timingsByCity?city=${Uri.encodeComponent(city)}&country=Turkey&method=13',
      );
      final r = await http.get(u);
      if (r.statusCode != 200) throw Exception();
      final data = jsonDecode(r.body)['data']['timings'] as Map<String,dynamic>;
      final result = <String,String>{};
      for (var i=0;i<apiNames.length;i++) {
        result[prayerNames[i]] = data[apiNames[i]].toString().substring(0,5);
      }
      setState(() => times = result);
      if (notificationsEnabled) await schedulePrayerNotifications(result);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Namaz vakitleri alınamadı. İnternet bağlantınızı kontrol edin.')),
      );
    } finally { if (mounted) setState(() => loading = false); }
  }

  Future<void> schedulePrayerNotifications(Map<String,String> data) async {
    await notifier.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool('notifications') ?? false)) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'prayer_times',
        'Namaz Vakitleri',
        channelDescription:'Namaz vakti bildirimleri',
        importance:Importance.max,
        priority:Priority.high,
        playSound:true,
      ),
      iOS: DarwinNotificationDetails(),
    );

    final location = tz.getLocation('Europe/Istanbul');
    final now = tz.TZDateTime.now(location);
    int id = 100;
    for (final e in data.entries) {
      final parts = e.value.split(':');
      var when = tz.TZDateTime(location, now.year, now.month, now.day,
        int.parse(parts[0]), int.parse(parts[1]));
      if (!when.isAfter(now)) when = when.add(const Duration(days:1));
      await notifier.zonedSchedule(
        id++, 'Ezan Vakti Türkiye', '${e.key} vakti: ${e.value}',
        when, details, androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    }
  }

  Future<void> toggleNotifications(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('notifications', value);
    if (value) {
      final android = notifier.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      final ios = notifier.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      await ios?.requestPermissions(alert:true,badge:true,sound:true);
    } else {
      await notifier.cancelAll();
    }
    setState(() => notificationsEnabled = value);
    if (value && times.isNotEmpty) await schedulePrayerNotifications(times);
  }

  Future<void> useLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Konum servisini açın.')));
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Konum izni verilmedi.')));
      return;
    }
    final pos = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy:LocationAccuracy.high));
    final geo = Geocoding(locale: const Locale('tr','TR'));
    final marks = await geo.placemarkFromCoordinates(pos.latitude,pos.longitude);
    if (marks.isNotEmpty) {
      final m=marks.first;
      final detectedCity = (m.administrativeArea ?? '').trim();
      final detectedDistrict = (m.subAdministrativeArea ?? m.locality ?? 'Merkez').trim();
      if (detectedCity.isNotEmpty && provinces.contains(detectedCity)) {
        final p=await SharedPreferences.getInstance();
        await p.setString('city',detectedCity);
        await p.setString('district',detectedDistrict);
        setState(() { city=detectedCity; district=detectedDistrict; });
        await loadTimes();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(city:city,district:district,times:times,loading:loading,onRefresh:loadTimes,onCity:chooseCity),
      const DuaTab(),
      const NamazTab(),
      const QiblaTab(),
      SettingsTab(enabled:notificationsEnabled,onNotifications:toggleNotifications,onLocation:useLocation),
    ];
    return Scaffold(
      body: SafeArea(child: pages[index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex:index,
        onDestinationSelected:(i)=>setState(()=>index=i),
        destinations:const [
          NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Ana Sayfa'),
          NavigationDestination(icon:Icon(Icons.auto_awesome_outlined),selectedIcon:Icon(Icons.auto_awesome),label:'Dua'),
          NavigationDestination(icon:Icon(Icons.mosque_outlined),selectedIcon:Icon(Icons.mosque),label:'Namaz'),
          NavigationDestination(icon:Icon(Icons.explore_outlined),selectedIcon:Icon(Icons.explore),label:'Kıble'),
          NavigationDestination(icon:Icon(Icons.settings_outlined),selectedIcon:Icon(Icons.settings),label:'Ayarlar'),
        ],
      ),
    );
  }

  Future<void> chooseCity() async {
    final chosen = await showSearch<String>(context:context, delegate:CitySearchDelegate());
    if (chosen == null) return;
    final p=await SharedPreferences.getInstance();
    await p.setString('city',chosen); await p.setString('district','Merkez');
    setState(() {city=chosen;district='Merkez';});
    await loadTimes();
  }
}

class CitySearchDelegate extends SearchDelegate<String> {
  @override List<Widget>? buildActions(BuildContext c)=>[IconButton(onPressed:()=>query='',icon:const Icon(Icons.clear))];
  @override Widget? buildLeading(BuildContext c)=>IconButton(onPressed:()=>close(c,null),icon:const Icon(Icons.arrow_back));
  @override Widget buildResults(BuildContext c)=>_list();
  @override Widget buildSuggestions(BuildContext c)=>_list();
  Widget _list()=>ListView(children:provinces.where((x)=>x.toLowerCase().contains(query.toLowerCase())).map(
    (x)=>ListTile(title:Text(x),trailing:const Icon(Icons.chevron_right),onTap:()=>close(context,x))).toList());
}

class HomeTab extends StatelessWidget {
  final String city,district; final Map<String,String> times; final bool loading;
  final Future<void> Function() onRefresh; final VoidCallback onCity;
  const HomeTab({super.key,required this.city,required this.district,required this.times,required this.loading,required this.onRefresh,required this.onCity});
  @override Widget build(BuildContext context)=>RefreshIndicator(
    onRefresh:onRefresh,
    child:ListView(padding:const EdgeInsets.all(18),children:[
      Container(
        padding:const EdgeInsets.all(20),
        decoration:BoxDecoration(borderRadius:BorderRadius.circular(28),gradient:const LinearGradient(colors:[darkGreen,green])),
        child:Column(children:[
          Row(children:[
            const Icon(Icons.location_on,color:gold),const SizedBox(width:6),
            Expanded(child:GestureDetector(onTap:onCity,child:Text('$city • $district ˅',style:const TextStyle(color:Colors.white,fontSize:20,fontWeight:FontWeight.bold)))),
            Text(DateFormat('d MMM', 'tr_TR').format(DateTime.now()),style:const TextStyle(color:Colors.white70)),
          ]),
          const SizedBox(height:22),
          const Text('Bir sonraki vakit',style:TextStyle(color:Colors.white70)),
          const SizedBox(height:4),
          Text(nextName(times),style:const TextStyle(color:Colors.white,fontSize:30,fontWeight:FontWeight.bold)),
          const SizedBox(height:4),
          Text(countdown(times),style:const TextStyle(color:gold,fontSize:25,fontWeight:FontWeight.bold)),
        ]),
      ),
      const SizedBox(height:18),
      if(loading) const Padding(padding:EdgeInsets.all(35),child:Center(child:CircularProgressIndicator()))
      else Card(elevation:0,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(22)),child:Column(
        children:times.entries.map((e)=>ListTile(
          leading:Icon(prayerIcon(e.key),color:green),
          title:Text(e.key,style:const TextStyle(fontWeight:FontWeight.w600)),
          trailing:Text(e.value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
        )).toList(),
      )),
      const SizedBox(height:12),
      const Card(elevation:0,child:Padding(padding:EdgeInsets.all(18),child:Text(
        '“Şüphesiz namaz, hayâsızlıktan ve kötülükten alıkoyar.”\nAnkebût, 45',
        style:TextStyle(fontSize:14),
      ))),
    ]),
  );
}

String nextName(Map<String,String> times) {
  final now=DateTime.now();
  for(final e in times.entries) {
    final p=e.value.split(':'); final d=DateTime(now.year,now.month,now.day,int.parse(p[0]),int.parse(p[1]));
    if(d.isAfter(now)) return e.key;
  }
  return 'İmsak';
}
String countdown(Map<String,String> times) {
  if(times.isEmpty) return '--:--:--';
  final now=DateTime.now(); DateTime? target;
  for(final e in times.entries) {
    final p=e.value.split(':'); final d=DateTime(now.year,now.month,now.day,int.parse(p[0]),int.parse(p[1]));
    if(d.isAfter(now)){target=d;break;}
  }
  target ??= DateTime(now.year,now.month,now.day+1, int.parse(times['İmsak']!.split(':')[0]), int.parse(times['İmsak']!.split(':')[1]));
  final d=target.difference(now);
  return '${d.inHours.toString().padLeft(2,'0')}:${(d.inMinutes%60).toString().padLeft(2,'0')}:${(d.inSeconds%60).toString().padLeft(2,'0')}';
}
IconData prayerIcon(String x)=>x=='İmsak'||x=='Yatsı'?Icons.nightlight_round:x=='Akşam'?Icons.wb_twilight:Icons.wb_sunny;

class DuaItem {
  final String title, arabic, translit, meaning;
  const DuaItem(this.title, this.arabic, this.translit, this.meaning);
}

const duaCategories = <String, List<DuaItem>>{
  'Sabah': [
    DuaItem(
      'Âyetü’l-Kürsî',
      'اللَّهُ لَا إِلَٰهَ إِلَّا هُوَ الْحَيُّ الْقَيُّومُ',
      'Allâhu lâ ilâhe illâ hüvel hayyül kayyûm.',
      'Allah, kendisinden başka ilâh olmayandır; diridir, kayyûmdur.',
    ),
    DuaItem(
      'Güne Başlarken',
      'الْحَمْدُ لِلَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا',
      'Elhamdülillâhillezî ahyânâ ba‘de mâ emâtenâ.',
      'Bizi öldürdükten sonra dirilten Allah’a hamdolsun.',
    ),
  ],
  'Akşam': [
    DuaItem(
      'Akşam Zikri',
      'اللَّهُمَّ أَنْتَ رَبِّي لَا إِلَٰهَ إِلَّا أَنْتَ',
      'Allahümme ente rabbî lâ ilâhe illâ ente.',
      'Allah’ım! Sen benim Rabbimsin. Senden başka ilâh yoktur.',
    ),
    DuaItem(
      'Akşam İçin Hamd',
      'اللَّهُمَّ بِكَ أَمْسَيْنَا وَبِكَ أَصْبَحْنَا',
      'Allahümme bike emseynâ ve bike asbahnâ.',
      'Allah’ım! Senin yardımınla akşama girdik ve Senin yardımınla sabahladık.',
    ),
  ],
  'Yemek': [
    DuaItem(
      'Yemek Öncesi',
      'بِسْمِ اللَّهِ',
      'Bismillâh.',
      'Allah’ın adıyla.',
    ),
    DuaItem(
      'Yemek Sonrası',
      'الْحَمْدُ لِلَّهِ الَّذِي أَطْعَمَنِي هَذَا وَرَزَقَنِيهِ',
      'Elhamdülillâhillezî at‘amenî hâzâ ve razakanîhi.',
      'Bunu bana yediren ve onu bana rızık olarak veren Allah’a hamdolsun.',
    ),
  ],
  'Uyku': [
    DuaItem(
      'Uyku Duası',
      'بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا',
      'Bismikellâhümme emûtu ve ahyâ.',
      'Allah’ım! Senin adınla ölür ve Senin adınla dirilirim.',
    ),
  ],
  'Rızık': [
    DuaItem(
      'Helal Rızık Duası',
      'اللَّهُمَّ إِنِّي أَسْأَلُكَ رِزْقًا طَيِّبًا',
      'Allahümme innî es’elüke rizkan tayyiben.',
      'Allah’ım! Senden temiz ve güzel bir rızık isterim.',
    ),
  ],
  'Korunma': [
    DuaItem(
      'Korunma Duası',
      'أَعُوذُ بِكَلِمَاتِ اللَّهِ التَّامَّاتِ مِنْ شَرِّ مَا خَلَقَ',
      'Eûzü bi-kelimâtillâhit-tâmmâti min şerri mâ halak.',
      'Allah’ın eksiksiz kelimelerine, yarattıklarının şerrinden sığınırım.',
    ),
  ],
  'Peygamber Duaları': [
    DuaItem(
      'Rabbena Âtinâ',
      'رَبَّنَا آتِنَا فِي الدُّنْيَا حَسَنَةً وَفِي الْآخِرَةِ حَسَنَةً',
      'Rabbenâ âtinâ fid-dünyâ haseneten ve fil-âhireti haseneten.',
      'Rabbimiz! Bize dünyada da iyilik ver, ahirette de iyilik ver.',
    ),
    DuaItem(
      'Rabbî Zıdnî İlmâ',
      'رَبِّ زِدْنِي عِلْمًا',
      'Rabbi zidnî ilmâ.',
      'Rabbim! İlmimi artır.',
    ),
  ],
};

class DuaTab extends StatefulWidget {
  const DuaTab({super.key});
  @override State<DuaTab> createState() => _DuaTabState();
}

class _DuaTabState extends State<DuaTab> {
  String selected = 'Sabah';

  @override
  Widget build(BuildContext context) {
    final items = duaCategories[selected]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        const Text('Dualar', style: TextStyle(fontSize:29,fontWeight:FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Günlük hayatınızda okuyabileceğiniz dualar', style: TextStyle(color:Colors.grey)),
        const SizedBox(height: 14),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: duaCategories.keys.map((name) => Padding(
              padding: const EdgeInsets.only(right:8),
              child: ChoiceChip(
                label: Text(name),
                selected: selected == name,
                onSelected: (_) => setState(() => selected = name),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 12),
        ...items.map((d) => Card(
          elevation:0,
          margin: const EdgeInsets.only(bottom:12),
          shape: RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DuaDetailPage(dua:d))),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
                Row(children:[
                  const CircleAvatar(backgroundColor:Color(0xFFE2F2EA),child:Icon(Icons.auto_awesome,color:green)),
                  const SizedBox(width:10),
                  Expanded(child:Text(d.title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))),
                  const Icon(Icons.chevron_right),
                ]),
                const SizedBox(height:15),
                Text(d.arabic,textAlign:TextAlign.right,style:const TextStyle(fontSize:23,height:1.7)),
                const SizedBox(height:8),
                Text(d.meaning,style:const TextStyle(color:Colors.grey)),
              ]),
            ),
          ),
        )),
      ],
    );
  }
}

class DuaDetailPage extends StatefulWidget {
  final DuaItem dua;
  const DuaDetailPage({super.key, required this.dua});
  @override State<DuaDetailPage> createState() => _DuaDetailPageState();
}

class _DuaDetailPageState extends State<DuaDetailPage> {
  bool playing = false;
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    appBar: AppBar(title: Text(widget.dua.title),backgroundColor:Colors.transparent),
    body: ListView(padding:const EdgeInsets.all(20),children:[
      Card(
        elevation:0,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),
        child:Padding(padding:const EdgeInsets.all(22),child:Column(children:[
          Text(widget.dua.arabic,textAlign:TextAlign.center,style:const TextStyle(fontSize:29,height:1.8)),
          const Divider(height:35),
          Align(alignment:Alignment.centerLeft,child:const Text('Okunuş',style:TextStyle(fontWeight:FontWeight.bold))),
          const SizedBox(height:8),
          Text(widget.dua.translit,style:const TextStyle(fontSize:17,height:1.5)),
          const SizedBox(height:20),
          Align(alignment:Alignment.centerLeft,child:const Text('Anlamı',style:TextStyle(fontWeight:FontWeight.bold))),
          const SizedBox(height:8),
          Text(widget.dua.meaning,style:const TextStyle(fontSize:17,height:1.5,color:Colors.grey)),
        ])),
      ),
      const SizedBox(height:14),
      FilledButton.icon(
        onPressed:()=>setState(()=>playing=!playing),
        icon:Icon(playing?Icons.stop_circle:Icons.volume_up),
        label:Text(playing?'Sesli okuma durdur':'Sesli okumayı başlat'),
      ),
      if(playing) const Padding(
        padding:EdgeInsets.only(top:8),
        child:Text('Sesli okuma özelliği için uygulamanın ses dosyaları yayın sürümüne eklenecek.',textAlign:TextAlign.center,style:TextStyle(color:Colors.grey)),
      ),
    ]),
  );
}


class PrayerStep {
  final int no;
  final String title, detail, image;
  const PrayerStep(this.no, this.title, this.detail, this.image);
}

const prayerGuides = <String, List<PrayerStep>>{
  'Sabah': [
    PrayerStep(1, 'Niyet', 'Sabah namazının 2 rekât sünneti için niyet edilir. Ardından tekbir alınarak namaza başlanır.', 'namaz_niyet.svg'),
    PrayerStep(2, 'Kıyam', 'Ayakta Sübhaneke, ardından Eûzü-Besmele, Fâtiha ve bir sûre okunur.', 'namaz_kavim.svg'),
    PrayerStep(3, 'Rükû', 'Tekbirle rükûya gidilir. Rükû tesbihi okunur ve doğrulunur.', 'namaz_ruku.svg'),
    PrayerStep(4, 'Secde', 'İki secde yapılır. İkinci secdeden sonra ikinci rekâta kalkılır.', 'namaz_secde.svg'),
    PrayerStep(5, 'İkinci rekât', 'Fâtiha ve bir sûre okunur; rükû ve iki secde yapılır.', 'namaz_kavim.svg'),
    PrayerStep(6, 'Kade-i ahîre', 'Oturulur; Ettehiyyâtü, Salli-Bârik ve dua okunur. Sağa ve sola selam verilerek namaz tamamlanır.', 'namaz_oturus.svg'),
  ],
  'Öğle': [
    PrayerStep(1, '4 rekât sünnet', 'Öğle namazının ilk 4 rekât sünneti kılınır. Her rekâtta Fâtiha ve sûre okunur; iki rekâtta bir oturuş yapılır.', 'namaz_kavim.svg'),
    PrayerStep(2, '4 rekât farz', 'Niyet ve tekbirden sonra ilk iki rekâtta Fâtiha ve sûre, sonraki rekâtlarda Fâtiha okunarak namaz tamamlanır.', 'namaz_kavim.svg'),
    PrayerStep(3, '2 rekât son sünnet', 'Farzdan sonra 2 rekât sünnet kılınır. Her iki rekâtta Fâtiha ve sûre okunur.', 'namaz_kavim.svg'),
  ],
  'İkindi': [
    PrayerStep(1, '4 rekât sünnet', 'İkindinin 4 rekât sünneti kılınır. Niyet, kıyam, rükû, secdeler ve oturuşlar sırayla yapılır.', 'namaz_kavim.svg'),
    PrayerStep(2, '4 rekât farz', 'Niyet edilerek farza başlanır. İlk iki rekâtta Fâtiha ve sûre, sonraki rekâtlarda Fâtiha okunur.', 'namaz_kavim.svg'),
    PrayerStep(3, 'Selam', 'Son oturuşta dualar okunur ve sağa-sola selam verilir.', 'namaz_kavim.svg'),
  ],
  'Akşam': [
    PrayerStep(1, '3 rekât farz', 'Akşam namazının 3 rekât farzı kılınır. İlk iki rekâtta Fâtiha ve sûre, üçüncü rekâtta Fâtiha okunur.', 'namaz_kavim.svg'),
    PrayerStep(2, 'Son oturuş', 'Üçüncü rekâtın ardından oturulur; dualar okunur ve selam verilir.', 'namaz_kavim.svg'),
    PrayerStep(3, '2 rekât sünnet', 'Farzdan sonra 2 rekât sünnet kılınır; iki rekâtta da Fâtiha ve sûre okunur.', 'namaz_kavim.svg'),
  ],
  'Yatsı': [
    PrayerStep(1, '4 rekât ilk sünnet', 'Yatsının ilk 4 rekât sünneti kılınır.', 'namaz_kavim.svg'),
    PrayerStep(2, '4 rekât farz', 'İlk iki rekâtta Fâtiha ve sûre, sonraki iki rekâtta Fâtiha okunur.', 'namaz_kavim.svg'),
    PrayerStep(3, '2 rekât son sünnet', 'Farzdan sonra 2 rekât sünnet kılınır.', 'namaz_kavim.svg'),
    PrayerStep(4, '3 rekât vitir', 'Vitir namazı ayrıca kılınır. Üçüncü rekâtta kunut duaları okunur ve selam verilir.', 'namaz_kavim.svg'),
  ],
};

class NamazTab extends StatefulWidget {
  const NamazTab({super.key});
  @override State<NamazTab> createState() => _NamazTabState();
}

class _NamazTabState extends State<NamazTab> {
  String selected = 'Sabah';

  @override
  Widget build(BuildContext context) {
    final steps = prayerGuides[selected]!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      children: [
        const Text('Namaz Nasıl Kılınır?', style: TextStyle(fontSize:29,fontWeight:FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Temel rehber • Hanefî uygulamasına göre özet', style: TextStyle(color:Colors.grey)),
        const SizedBox(height: 14),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: prayerGuides.keys.map((name) => Padding(
              padding: const EdgeInsets.only(right:8),
              child: ChoiceChip(
                label: Text(name),
                selected: selected == name,
                onSelected: (_) => setState(() => selected = name),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 14),
        ...steps.map((s) => Card(
          elevation:0,
          margin:const EdgeInsets.only(bottom:10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFFE2F2EA),
              child: Text('${s.no}',style:const TextStyle(color:green,fontWeight:FontWeight.bold)),
            ),
            title: Text(s.title,style:const TextStyle(fontWeight:FontWeight.bold)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top:6),
              child: Text(s.detail),
            ),
          ),
        )),
        const SizedBox(height:4),
        const Card(
          elevation:0,
          child: Padding(
            padding: EdgeInsets.all(15),
            child: Text(
              'Not: Bu ekran başlangıç rehberidir. Mezhep ve uygulama farklılıkları bulunabilir. Ayrıntılı ilmihal bilgisi için güvenilir bir din görevlisine veya yetkin ilmihal kaynağına başvurulmalıdır.',
              style: TextStyle(color:Colors.grey),
            ),
          ),
        ),
      ],
    );
  }
}


class PrayerStepPage extends StatelessWidget {
  final PrayerStep step;
  const PrayerStepPage({super.key, required this.step});
  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:cream,
    appBar:AppBar(title:Text(step.title),backgroundColor:Colors.transparent),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      Card(
        elevation:0,
        shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(24)),
        child:Padding(padding:const EdgeInsets.all(20),child:Column(children:[
          Image.asset('assets/${step.image}',height:210),
          const SizedBox(height:15),
          Text('${step.no}. ${step.title}',style:const TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
          const SizedBox(height:12),
          Text(step.detail,style:const TextStyle(fontSize:17,height:1.55)),
        ])),
      ),
      const SizedBox(height:12),
      const Card(elevation:0,child:Padding(
        padding:EdgeInsets.all(16),
        child:Text('Bu anlatım başlangıç seviyesinde bir rehberdir. Uygulama farklılıkları olabilir; ayrıntılar için güvenilir ilmihal kaynaklarına başvurun.',style:TextStyle(color:Colors.grey)),
      )),
    ]),
  );
}

class QiblaTab extends StatefulWidget {
  const QiblaTab({super.key});
  @override State<QiblaTab> createState()=>_QiblaTabState();
}
class _QiblaTabState extends State<QiblaTab> {
  double? bearing; double? heading; String place='Konum alınmadı'; bool loading=false;
  @override void initState(){super.initState(); init();}
  Future<void> init() async {
    setState(()=>loading=true);
    try {
      var p=await Geolocator.checkPermission();
      if(p==LocationPermission.denied) p=await Geolocator.requestPermission();
      if(p==LocationPermission.denied||p==LocationPermission.deniedForever) return;
      final pos=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high));
      bearing=qiblaBearing(pos.latitude,pos.longitude);
      final geo = Geocoding(locale: const Locale('tr','TR')); final marks=await geo.placemarkFromCoordinates(pos.latitude,pos.longitude);
      if(marks.isNotEmpty) place='${marks.first.administrativeArea ?? ''} • ${marks.first.subAdministrativeArea ?? marks.first.locality ?? ''}';
    } finally { if(mounted)setState(()=>loading=false); }
  }
  @override Widget build(BuildContext c)=>StreamBuilder<CompassEvent>(
    stream:FlutterCompass.events,
    builder:(c,s){
      heading=s.data?.heading;
      final rotation=((bearing??0)-(heading??0))*math.pi/180;
      return Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        const Text('Kıble Yönü',style:TextStyle(fontSize:30,fontWeight:FontWeight.bold)),
        const SizedBox(height:22),
        Transform.rotate(angle:rotation,child:Container(width:270,height:270,decoration:BoxDecoration(shape:BoxShape.circle,gradient:const RadialGradient(colors:[green,darkGreen]),border:Border.all(color:gold,width:6)),child:const Icon(Icons.navigation,size:115,color:gold))),
        const SizedBox(height:20),
        Text(loading?'Konum alınıyor…':bearing==null?'Konum izni gerekli':'Kıble: ${bearing!.toStringAsFixed(0)}°'),
        const SizedBox(height:5),Text(place,style:const TextStyle(color:Colors.grey)),
        const SizedBox(height:12),const Text('Telefonu düz tutun ve pusula kalibrasyonu yapın.',style:TextStyle(color:Colors.grey)),
      ]));
    },
  );
}

double qiblaBearing(double lat,double lon) {
  const kaabaLat=21.422487, kaabaLon=39.826206;
  final p1=lat*math.pi/180,p2=kaabaLat*math.pi/180,dLon=(kaabaLon-lon)*math.pi/180;
  final y=math.sin(dLon), x=math.cos(p1)*math.tan(p2)-math.sin(p1)*math.cos(dLon);
  return (math.atan2(y,x)*180/math.pi+360)%360;
}

class SettingsTab extends StatelessWidget {
  final bool enabled; final ValueChanged<bool> onNotifications; final Future<void> Function() onLocation;
  const SettingsTab({super.key,required this.enabled,required this.onNotifications,required this.onLocation});
  @override Widget build(BuildContext c)=>ListView(padding:const EdgeInsets.all(20),children:[
    const Text('Ayarlar',style:TextStyle(fontSize:29,fontWeight:FontWeight.bold)),
    const SizedBox(height:14),
    Card(child:SwitchListTile(
      value:enabled,
      onChanged:onNotifications,
      secondary:const Icon(Icons.notifications_active),
      title:const Text('Ezan Bildirimleri'),
      subtitle:const Text('Vakit geldiğinde bildirim gönder'),
    )),
    Card(child:ListTile(
      leading:const Icon(Icons.volume_up),
      title:const Text('Bildirim Sesi'),
      subtitle:const Text('Yayın sürümünde lisanslı ezan kaydı eklenebilir'),
    )),
    Card(child:ListTile(leading:const Icon(Icons.my_location),title:const Text('Konumumu Kullan'),subtitle:const Text('İl ve ilçeyi otomatik belirle'),onTap:onLocation)),
    Card(child:ListTile(leading:const Icon(Icons.privacy_tip),title:const Text('Gizlilik Politikası'),onTap:()=>showDialog(context:c,builder:(_)=>const AlertDialog(title:Text('Gizlilik'),content:Text('Konum yalnızca vakit ve kıble özellikleri için kullanılabilir. Kullanıcı izinleri cihaz ayarlarından yönetilir.'))))),
  ]);
}
