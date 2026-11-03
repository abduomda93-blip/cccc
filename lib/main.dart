// lib/main.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('trip_logs');
  await Hive.openBox('settings');
  runApp(const CarTrackerApp());
}

class CarTrackerApp extends StatefulWidget {
  const CarTrackerApp({super.key});

  @override
  State<CarTrackerApp> createState() => _CarTrackerAppState();
}

class _CarTrackerAppState extends State<CarTrackerApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme(bool isDark) {
    setState(() {
      _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'سجل السيارات اليومي',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      supportedLocales: const [Locale('ar', 'SA')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: _themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFFF7F9FC),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: HomeScreen(onToggleTheme: _toggleTheme),
    );
  }
}

class HomeScreen extends StatefulWidget {
  final Function(bool) onToggleTheme;
  const HomeScreen({super.key, required this.onToggleTheme});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final Box tripBox = Hive.box('trip_logs');
  final Box settingsBox = Hive.box('settings');

  @override
  Widget build(BuildContext context) {
    final screens = [
      AddTripScreen(tripBox: tripBox, settingsBox: settingsBox),
      ReportsScreen(tripBox: tripBox),
      SettingsScreen(
        settingsBox: settingsBox,
        tripBox: tripBox,
        onToggleTheme: widget.onToggleTheme,
      ),
    ];

    return Scaffold(
      body: screens[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.add_road), label: 'تسجيل رحلة'),
          NavigationDestination(icon: Icon(Icons.analytics_outlined), label: 'السجلات والتقارير'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: 'الإعدادات'),
        ],
      ),
    );
  }
}

// واجهة إدخال البيانات اليومية
class AddTripScreen extends StatefulWidget {
  final Box tripBox;
  final Box settingsBox;
  const AddTripScreen({super.key, required this.tripBox, required this.settingsBox});

  @override
  State<AddTripScreen> createState() => _AddTripScreenState();
}

class _AddTripScreenState extends State<AddTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _plateController = TextEditingController();
  final _modelController = TextEditingController();
  final _driverController = TextEditingController();
  final _startMeterController = TextEditingController();
  final _endMeterController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  double _calculatedDistance = 0.0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _startMeterController.addListener(_calculateDistance);
    _endMeterController.addListener(_calculateDistance);
  }

  void _calculateDistance() {
    final double start = double.tryParse(_startMeterController.text) ?? 0.0;
    final double end = double.tryParse(_endMeterController.text) ?? 0.0;
    setState(() {
      _calculatedDistance = (end >= start) ? (end - start) : 0.0;
    });
  }

  void _onPlateChanged(String plate) {
    if (plate.trim().isEmpty) return;
    final trips = widget.tripBox.values.toList();
    for (int i = trips.length - 1; i >= 0; i--) {
      final trip = Map<String, dynamic>.from(trips[i]);
      if (trip['plateNumber'].toString().trim().toLowerCase() == plate.trim().toLowerCase()) {
        setState(() {
          _startMeterController.text = trip['endMeter'].toString();
          if (_modelController.text.isEmpty && trip['carModel'] != null) {
            _modelController.text = trip['carModel'];
          }
          if (_driverController.text.isEmpty && trip['driverName'] != null) {
            _driverController.text = trip['driverName'];
          }
        });
        break;
      }
    }
  }

  Future<void> _saveTrip() async {
    if (!_formKey.currentState!.validate()) return;
    final double start = double.parse(_startMeterController.text);
    final double end = double.parse(_endMeterController.text);

    if (end < start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('خطأ: عداد الرجوع لا يمكن أن يكون أقل من عداد الخروج!'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    final String tripId = DateTime.now().millisecondsSinceEpoch.toString();
    final newTrip = {
      'id': tripId,
      'plateNumber': _plateController.text.trim(),
      'carModel': _modelController.text.trim(),
      'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
      'driverName': _driverController.text.trim(),
      'startMeter': start,
      'endMeter': end,
      'distance': end - start,
      'startTime': _startTime?.format(context) ?? '',
      'endTime': _endTime?.format(context) ?? '',
      'notes': _notesController.text.trim(),
      'synced': false,
    };

    await widget.tripBox.put(tripId, newTrip);

    final scriptUrl = widget.settingsBox.get('sheets_url', defaultValue: '');
    if (scriptUrl.toString().trim().isNotEmpty) {
      try {
        final res = await http.post(
          Uri.parse(scriptUrl),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(newTrip),
        );
        if (res.statusCode == 200 || res.statusCode == 302) {
          newTrip['synced'] = true;
          await widget.tripBox.put(tripId, newTrip);
        }
      } catch (e) {
        debugPrint('Cloud sync error: $e');
      }
    }

    setState(() => _isLoading = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ وتوثيق الرحلة بنجاح'), backgroundColor: Colors.teal),
    );
    _resetForm();
  }

  void _resetForm() {
    _plateController.clear();
    _modelController.clear();
    _driverController.clear();
    _startMeterController.clear();
    _endMeterController.clear();
    _notesController.clear();
    setState(() {
      _selectedDate = DateTime.now();
      _startTime = null;
      _endTime = null;
      _calculatedDistance = 0.0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تسجيل رحلة يومية'), centerTitle: true),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _plateController,
                        decoration: const InputDecoration(
                          labelText: 'رقم اللوحة / السيارة *',
                          prefixIcon: Icon(Icons.directions_car),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'هذا الحقل إجباري' : null,
                        onChanged: _onPlateChanged,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _modelController,
                        decoration: const InputDecoration(
                          labelText: 'موديل / نوع السيارة (اختياري)',
                          prefixIcon: Icon(Icons.car_repair),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _driverController,
                        decoration: const InputDecoration(
                          labelText: 'اسم السائق (اختياري)',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_month, color: Colors.teal),
                        title: Text('تاريخ الرحلة: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}'),
                        trailing: ElevatedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2035),
                            );
                            if (picked != null) setState(() => _selectedDate = picked);
                          },
                          child: const Text('تغيير'),
                        ),
                      ),
                      const Divider(),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.access_time),
                              label: Text(_startTime == null ? 'وقت الخروج' : _startTime!.format(context)),
                              onPressed: () async {
                                final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                                if (t != null) setState(() => _startTime = t);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.timelapse),
                              label: Text(_endTime == null ? 'وقت الرجوع' : _endTime!.format(context)),
                              onPressed: () async {
                                final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                                if (t != null) setState(() => _endTime = t);
                              },
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _startMeterController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'عداد الخروج (كم) *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _endMeterController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'عداد الرجوع (كم) *',
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v == null || v.isEmpty ? 'مطلوب' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'إجمالي المسافة المقطوعة:',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              '${_calculatedDistance.toStringAsFixed(1)} كم',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.teal),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات (صولار، صيانة، تفاصيل...)',
                          prefixIcon: Icon(Icons.note_alt_outlined),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _saveTrip,
                  icon: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                      : const Icon(Icons.save),
                  label: const Text('حفظ وتسجيل الرحلة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// شاشة التقارير والسجلات
class ReportsScreen extends StatefulWidget {
  final Box tripBox;
  const ReportsScreen({super.key, required this.tripBox});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String _searchPlate = '';

  List<Map<String, dynamic>> _getFilteredTrips() {
    final rawList = widget.tripBox.values.toList();
    List<Map<String, dynamic>> trips = [];
    for (var item in rawList) {
      trips.add(Map<String, dynamic>.from(item));
    }
    trips.sort((a, b) => (b['id'] ?? '').toString().compareTo(a['id'] ?? ''));
    return trips.where((trip) {
      return _searchPlate.isEmpty ||
          (trip['plateNumber'] ?? '').toString().toLowerCase().contains(_searchPlate.toLowerCase());
    }).toList();
  }

  Future<void> _exportToCsv(List<Map<String, dynamic>> trips) async {
    if (trips.isEmpty) return;
    List<List<dynamic>> rows = [
      ["معرف الرحلة", "التاريخ", "رقم اللوحة", "نوع السيارة", "السائق", "عداد الخروج", "عداد الرجوع", "المسافة", "ملاحظات"]
    ];
    for (var t in trips) {
      rows.add([t['id'], t['date'], t['plateNumber'], t['carModel'], t['driverName'], t['startMeter'], t['endMeter'], t['distance'], t['notes']]);
    }
    String csvData = const ListToCsvConverter().convert(rows);
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/report_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csvData);
    await Share.shareXFiles([XFile(file.path)], text: 'تقرير سجلات السيارات');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.tripBox.listenable(),
      builder: (context, Box box, _) {
        final trips = _getFilteredTrips();
        final totalDist = trips.fold(0.0, (sum, i) => sum + ((i['distance'] as num?)?.toDouble() ?? 0.0));
        return Scaffold(
          appBar: AppBar(
            title: const Text('السجلات والتقارير'),
            actions: [
              IconButton(icon: const Icon(Icons.file_download), onPressed: () => _exportToCsv(trips))
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            const Text('إجمالي الكيلومترات', style: TextStyle(color: Colors.white70)),
                            Text('${totalDist.toStringAsFixed(1)} كم', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.indigo.shade700, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            const Text('إجمالي الرحلات', style: TextStyle(color: Colors.white70)),
                            Text('${trips.length} رحلة', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  decoration: const InputDecoration(hintText: 'بحث برقم اللوحة...', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => _searchPlate = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: trips.length,
                  itemBuilder: (ctx, i) {
                    final t = trips[i];
                    return ListTile(
                      title: Text('${t['plateNumber']} - ${t['distance']} كم'),
                      subtitle: Text('التاريخ: ${t['date']} | السائق: ${t['driverName'] ?? ''}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => widget.tripBox.delete(t['id']),
                      ),
                    );
                  },
                ),
              )
            ],
          ),
        );
      },
    );
  }
}

// شاشة الإعدادات
class SettingsScreen extends StatefulWidget {
  final Box settingsBox;
  final Box tripBox;
  final Function(bool) onToggleTheme;
  const SettingsScreen({super.key, required this.settingsBox, required this.tripBox, required this.onToggleTheme});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _urlCtrl = TextEditingController();
  bool _dark = false;

  @override
  void initState() {
    super.initState();
    _urlCtrl.text = widget.settingsBox.get('sheets_url', defaultValue: '');
    _dark = widget.settingsBox.get('is_dark', defaultValue: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات والربط')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _urlCtrl,
            decoration: const InputDecoration(labelText: 'Google Apps Script URL', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () {
              widget.settingsBox.put('sheets_url', _urlCtrl.text.trim());
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الرابط بنجاح')));
            },
            child: const Text('حفظ رابط المزامنة'),
          ),
          SwitchListTile(
            title: const Text('الوضع الليلي'),
            value: _dark,
            onChanged: (v) {
              setState(() => _dark = v);
              widget.settingsBox.put('is_dark', v);
              widget.onToggleTheme(v);
            },
          ),
        ],
      ),
    );
  }
}
