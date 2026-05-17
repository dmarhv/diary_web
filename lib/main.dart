import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ru_RU', null);
  runApp(const PlannerApp());
}


const Color bgColor = Color(0xFFFAF8F5); // цвет фона
const Color primaryColor = Color(0xFFD4A373); // цвет кнопок
const Color chipBgColor = Color(0xFFF2EFE9); // Фон неактивных элементов
const Color textColorDark = Color(0xFF333333); // цвет основного текста
const Color textColorLight = Color(0xFF888888); // цвет второстепенного текста
const Color errorColor = Color(0xFFFDE8E8); // Цвет для просроченных дел

class PlannerApp extends StatelessWidget {
  const PlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ежедневник',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: bgColor,
        primaryColor: primaryColor,
        fontFamily: 'Roboto',
      ),
      home: const MainScreen(),
    );
  }
}

class Event {
  final String id;
  final String title;
  final DateTime dateTime;
  final int durationMinutes;
  final String location;

  Event({
    required this.id,
    required this.title,
    required this.dateTime,
    required this.durationMinutes,
    required this.location,
  });

  DateTime get endTime => dateTime.add(Duration(minutes: durationMinutes));

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dateTime': dateTime.toIso8601String(),
        'durationMinutes': durationMinutes,
        'location': location,
      };

  factory Event.fromJson(Map<String, dynamic> json) => Event(
        id: json['id'],
        title: json['title'],
        dateTime: DateTime.parse(json['dateTime']),
        durationMinutes: json['durationMinutes'],
        location: json['location'],
      );
}

// Главеный экран
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  List<Event> events = [];
  String selectedFilter = 'Все';
  final List<String> filters = ['Все', 'Сегодня', 'Завтра', 'Будущие'];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  // Загрузка данных
  Future<void> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final String? eventsJson = prefs.getString('saved_events');
    if (eventsJson != null) {
      final List<dynamic> decoded = jsonDecode(eventsJson);
      setState(() {
        events = decoded.map((item) => Event.fromJson(item)).toList();
      });
    }
    _cleanUpOldEvents();
  }

  // Сохранение данных
  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(events.map((e) => e.toJson()).toList());
    await prefs.setString('saved_events', encoded);
  }

  // Удаление вчерашних дел (как просили в ТЗ)
  void _cleanUpOldEvents() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      events.removeWhere((e) => e.dateTime.isBefore(today));
    });
    _saveEvents();
  }

  // Фильтрация событий для отображения
  List<Event> get filteredEvents {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    switch (selectedFilter) {
      case 'Сегодня':
        return events.where((e) => e.dateTime.year == today.year && e.dateTime.month == today.month && e.dateTime.day == today.day).toList();
      case 'Завтра':
        return events.where((e) => e.dateTime.year == tomorrow.year && e.dateTime.month == tomorrow.month && e.dateTime.day == tomorrow.day).toList();
      case 'Будущие':
        return events.where((e) => e.dateTime.isAfter(tomorrow.add(const Duration(days: 1, microseconds: -1)))).toList();
      case 'Все':
      default:
        return events;
    }
  }

  Event? get nextEvent {
    final now = DateTime.now();
    try {
      return events.firstWhere((e) => e.dateTime.isAfter(now));
    } catch (_) {
      return null;
    }
  }

  void _showAddEventBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEventSheet(
        onAddEvent: (newEvent) {
          // Анализ накладок
          bool hasOverlap = events.any((existingEvent) {
            return newEvent.dateTime.isBefore(existingEvent.endTime) &&
                newEvent.endTime.isAfter(existingEvent.dateTime);
          });

          if (hasOverlap) {
            return 'Внимание: Накладка времени с другим событием!';
          } else {
            setState(() {
              events.add(newEvent);
              events.sort((a, b) => a.dateTime.compareTo(b.dateTime));
            });
            _saveEvents();
            Navigator.pop(context);
            return null;
          }
        },
      ),
    );
  }

  void _showEditEventBottomSheet(Event event) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => AddEventSheet(
        event: event,
        onAddEvent: (updatedEvent) {
          // Анализ накладок (исключая саму себя)
          bool hasOverlap = events.any((existingEvent) {
            if (existingEvent.id == event.id) return false;
            return updatedEvent.dateTime.isBefore(existingEvent.endTime) &&
                updatedEvent.endTime.isAfter(existingEvent.dateTime);
          });

          if (hasOverlap) {
            return 'Внимание: Накладка времени с другим событием!';
          } else {
            setState(() {
              int index = events.indexWhere((e) => e.id == event.id);
              if (index != -1) {
                events[index] = updatedEvent;
                events.sort((a, b) => a.dateTime.compareTo(b.dateTime));
              }
            });
            _saveEvents();
            Navigator.pop(context);
            return null;
          }
        },
        onDelete: (id) {
          setState(() {
            events.removeWhere((e) => e.id == id);
          });
          _saveEvents();
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildUpcomingCard(Event event) {
    final timeLeft = event.dateTime.difference(DateTime.now());
    String timeStr = "";
    if (timeLeft.inDays > 0) {
      timeStr = "через ${timeLeft.inDays} дн";
    } else if (timeLeft.inHours > 0) {
      timeStr = "через ${timeLeft.inHours} ч";
    } else {
      timeStr = "через ${timeLeft.inMinutes} мин";
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Ближайшее событие',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              Text(
                timeStr,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            event.title,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.access_time_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Text(
                DateFormat('d MMM, HH:mm', 'ru_RU').format(event.dateTime),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 24),
              const Icon(Icons.location_on_rounded, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  event.location,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentDateStr = DateFormat('d MMMM yyyy, EEEE', 'ru_RU').format(DateTime.now());
    final closestEvent = nextEvent;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ежедневник', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: textColorDark)),
                      Text(currentDateStr, style: const TextStyle(fontSize: 14, color: textColorLight)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.notifications_none, color: textColorDark),
                  )
                ],
              ),
              const SizedBox(height: 24),

              // Виджет ближайшего события
              if (closestEvent != null) ...[
                _buildUpcomingCard(closestEvent),
                const SizedBox(height: 24),
              ],

              // Фильтры
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: filters.map((filter) {
                    bool isSelected = selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() => selectedFilter = filter);
                        },
                        selectedColor: primaryColor,
                        backgroundColor: chipBgColor,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.white : textColorDark,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        showCheckmark: false,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 30),

              const Text('Ваш список дел', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColorDark)),
              const SizedBox(height: 16),

              // Список или пустое состояние
              Expanded(
                child: filteredEvents.isEmpty
                    ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: chipBgColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.calendar_today_outlined, size: 40, color: primaryColor),
                      ),
                      const SizedBox(height: 20),
                      const Text('Нет запланированных событий', style: TextStyle(color: textColorLight)),
                      const SizedBox(height: 8),
                      const Text('Нажмите кнопку ниже, чтобы добавить новое', style: TextStyle(color: textColorLight, fontSize: 12)),
                    ],
                  ),
                )
                    : ListView.builder(
                  itemCount: filteredEvents.length,
                  itemBuilder: (context, index) {
                    final event = filteredEvents[index];
                    final isOverdue = event.dateTime.isBefore(DateTime.now());

                    return Card(
                      color: isOverdue ? errorColor : Colors.white,
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: isOverdue
                            ? const BorderSide(color: Colors.redAccent, width: 0.5)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        onTap: () => _showEditEventBottomSheet(event),
                        title: Text(
                          event.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isOverdue ? Colors.redAccent[700] : textColorDark,
                            decoration: isOverdue ? TextDecoration.lineThrough : null,
                          ),
                        ),
                        subtitle: Text(
                          '${DateFormat('d MMM, HH:mm', 'ru_RU').format(event.dateTime)} - ${event.location}',
                          style: TextStyle(color: isOverdue ? Colors.redAccent.withOpacity(0.7) : textColorLight),
                        ),
                        trailing: isOverdue
                            ? IconButton(
                                icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                                onPressed: () {
                                  setState(() {
                                    events.removeWhere((e) => e.id == event.id);
                                  });
                                  _saveEvents();
                                },
                                tooltip: 'Убрать',
                              )
                            : Text('${event.durationMinutes} мин', style: const TextStyle(color: primaryColor)),
                      ),
                    );
                  },
                ),
              ),

              // Кнопка добавления
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _showAddEventBottomSheet,
                  icon: const Icon(Icons.add, color: Colors.white),
                  label: const Text('Добавить событие', style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// === BOTTOM SHEET ДОБАВЛЕНИЯ И РЕДАКТИРОВАНИЯ СОБЫТИЯ ===
class AddEventSheet extends StatefulWidget {
  final String? Function(Event) onAddEvent;
  final Event? event;
  final Function(String)? onDelete;

  const AddEventSheet({
    super.key,
    required this.onAddEvent,
    this.event,
    this.onDelete,
  });

  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  final _titleController = TextEditingController();
  final _durationController = TextEditingController(text: '60');
  final _locationController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.event != null) {
      _titleController.text = widget.event!.title;
      _durationController.text = widget.event!.durationMinutes.toString();
      _locationController.text = widget.event!.location;
      _selectedDate = widget.event!.dateTime;
      _selectedTime = TimeOfDay.fromDateTime(widget.event!.dateTime);
    }
  }

  void _submit() {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Введите название события')));
      return;
    }
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите дату и время')));
      return;
    }

    final dateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final event = Event(
      id: widget.event?.id ?? DateTime.now().toString(),
      title: _titleController.text,
      dateTime: dateTime,
      durationMinutes: int.tryParse(_durationController.text) ?? 60,
      location: _locationController.text,
    );

    final error = widget.onAddEvent(event);
    if (error != null) {
      setState(() => _errorMessage = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 
                MediaQuery.of(context).padding.bottom + 20, // Учитываем клавиатуру и системную панель
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.event == null ? 'Новое событие' : 'Редактировать',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColorDark),
                ),
                Row(
                  children: [
                    if (widget.event != null)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => widget.onDelete?.call(widget.event!.id),
                      ),
                    IconButton(
                      icon: const Icon(Icons.close, color: textColorLight),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                )
              ],
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),

            _buildTextField('Название', 'Встреча с командой', _titleController),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) setState(() => _selectedDate = date);
                    },
                    child: _buildMockField('Дата', _selectedDate == null ? 'ДД.ММ.ГГГГ' : DateFormat('dd.MM.yyyy').format(_selectedDate!)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      final time = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.now(),
                      );
                      if (time != null) setState(() => _selectedTime = time);
                    },
                    child: _buildMockField('Время', _selectedTime == null ? '--:--' : _selectedTime!.format(context)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _buildTextField('Длительность (минут)', '60', _durationController, isNumber: true),
            const SizedBox(height: 16),

            _buildTextField('Место', 'Офис, комната 301', _locationController),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _submit,
                icon: Icon(widget.event == null ? Icons.add : Icons.save, color: Colors.white),
                label: Text(
                  widget.event == null ? 'Добавить событие' : 'Сохранить изменения',
                  style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, String hint, TextEditingController controller, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: textColorLight)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFFCCCCCC)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primaryColor)),
          ),
        ),
      ],
    );
  }

  // Визуальная имитация поля ввода для даты и времени (т.к. они открывают пикеры по нажатию)
  Widget _buildMockField(String label, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: textColorLight)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE0E0E0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(text, style: TextStyle(color: text.contains('-') || text.contains('Д') ? const Color(0xFFCCCCCC) : textColorDark)),
        ),
      ],
    );
  }
}
