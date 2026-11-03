import 'dart:convert';

import 'app_database.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const String _tasksKey = 'injaz_tasks_v1';
const String _settingsKey = 'injaz_settings_v1';
const String _listsKey = 'injaz_lists_v1';
const String _defaultListId = 'injaz_default_list';
const Color _purple = Color(0xFF6750A4);

enum TaskStatus { pending, done, notDone }

class PlannerTask {
  PlannerTask({
    required this.id,
    required this.dayKey,
    required this.text,
    required this.hour,
    required this.minute,
    required this.colorValue,
    this.status = TaskStatus.pending,
    this.repeatDaily = false,
    this.repeatDays = const <int>{},
    this.listId = _defaultListId,
    this.sortOrder = 0,
    this.snoozedUntil,
  });

  final String id;
  String dayKey;
  String text;
  int hour;
  int minute;
  int colorValue;
  TaskStatus status;
  bool repeatDaily;
  Set<int> repeatDays;
  String listId;
  int sortOrder;
  String? snoozedUntil;

  Map<String, dynamic> toJson() => {
        'id': id,
        'dayKey': dayKey,
        'text': text,
        'hour': hour,
        'minute': minute,
        'colorValue': colorValue,
        'status': status.name,
        'repeatDaily': repeatDaily,
        'repeatDays': repeatDays.toList()..sort(),
        'listId': listId,
        'sortOrder': sortOrder,
      };

  factory PlannerTask.fromJson(Map<String, dynamic> json) {
    return PlannerTask(
      id: json['id'] as String,
      dayKey: json['dayKey'] as String,
      text: json['text'] as String? ?? '',
      hour: json['hour'] as int? ?? 9,
      minute: json['minute'] as int? ?? 0,
      colorValue: json['colorValue'] as int? ?? _purple.value,
      status: TaskStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => TaskStatus.pending,
      ),
      repeatDaily: json['repeatDaily'] as bool? ?? false,
      repeatDays: ((json['repeatDays'] as List?) ?? const <dynamic>[]).whereType<num>().map((v) => v.toInt()).toSet(),
      listId: json['listId'] as String? ?? _defaultListId,
      sortOrder: json['sortOrder'] as int? ?? 0,
    );
  }

  int get notificationId {
    var hash = 17;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return 1000 + (hash % 800000000);
  }

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String timeLabelFor(bool english) {
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final suffix = english ? (hour < 12 ? 'AM' : 'PM') : (hour < 12 ? 'ص' : 'م');
    return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $suffix';
  }
}

class TaskGroup {
  TaskGroup({
    required this.id,
    required this.name,
    this.collapsed = false,
  });

  final String id;
  String name;
  bool collapsed;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'collapsed': collapsed,
      };

  factory TaskGroup.fromJson(Map<String, dynamic> json) => TaskGroup(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'قائمة جديدة',
        collapsed: json['collapsed'] as bool? ?? false,
      );
}

class PlannerSettings {
  bool darkMode;
  bool english;
  bool notificationsEnabled;
  int reminderHour;
  int reminderMinute;
  bool dailyReportEnabled;
  int dailyReportHour;
  int dailyReportMinute;

  PlannerSettings({
    this.darkMode = false,
    this.english = false,
    this.notificationsEnabled = true,
    this.reminderHour = 8,
    this.reminderMinute = 0,
    this.dailyReportEnabled = false,
    this.dailyReportHour = 20,
    this.dailyReportMinute = 0,
  });

  Map<String, dynamic> toJson() => {
        'darkMode': darkMode,
        'english': english,
        'notificationsEnabled': notificationsEnabled,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
        'dailyReportEnabled': dailyReportEnabled,
        'dailyReportHour': dailyReportHour,
        'dailyReportMinute': dailyReportMinute,
      };

  factory PlannerSettings.fromJson(Map<String, dynamic> json) =>
      PlannerSettings(
        darkMode: json['darkMode'] as bool? ?? false,
        english: json['english'] as bool? ?? false,
        notificationsEnabled:
            json['notificationsEnabled'] as bool? ?? true,
        reminderHour: json['reminderHour'] as int? ?? 8,
        reminderMinute: json['reminderMinute'] as int? ?? 0,
        dailyReportEnabled: json['dailyReportEnabled'] as bool? ?? false,
        dailyReportHour: json['dailyReportHour'] as int? ?? 20,
        dailyReportMinute: json['dailyReportMinute'] as int? ?? 0,
      );
}

String dayKeyOf(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

DateTime dateFromKey(String key) {
  final parts = key.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String formatDate(DateTime date, bool english) {
  const arDays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
  const enDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const arMonths = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
  const enMonths = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final day = english ? enDays[date.weekday - 1] : arDays[date.weekday - 1];
  final month = english ? enMonths[date.month - 1] : arMonths[date.month - 1];
  return english
      ? '$day, $month ${date.day}, ${date.year}'
      : '$day، ${date.day} $month ${date.year}';
}

Set<int> _decodeRepeatDays(String value) => value
    .split(',')
    .map(int.tryParse)
    .whereType<int>()
    .where((day) => day >= 1 && day <= 7)
    .toSet();

String _encodeRepeatDays(Iterable<int> days) => (days.toList()..sort()).join(',');

class PlannerController extends ChangeNotifier {
  PlannerController._(this.database);

  final AppDatabase database;
  final List<PlannerTask> tasks = [];
  final List<TaskGroup> groups = [];
  PlannerSettings settings = PlannerSettings();

  static Future<PlannerController> create() async {
    final database = await AppDatabase.open();
    final controller = PlannerController._(database);
    await controller.load();
    await controller.prepareNewDay();
    return controller;
  }

  Future<void> load() async {
    final listRows = await database.getLists();
    final taskRows = await database.getTasks();
    final settingRows = await database.getSettings();

    tasks
      ..clear()
      ..addAll(taskRows.map((row) => PlannerTask(
            id: row['id']! as String,
            dayKey: row['day_key']! as String,
            text: row['text']! as String,
            hour: row['hour']! as int,
            minute: row['minute']! as int,
            colorValue: row['color_value']! as int,
            status: TaskStatus.values.firstWhere(
              (value) => value.name == row['status'],
              orElse: () => TaskStatus.pending,
            ),
            repeatDaily: (row['repeat_daily'] as int? ?? 0) == 1,
            repeatDays: _decodeRepeatDays(row['repeat_days']?.toString() ?? ''),
            listId: row['list_id']! as String,
            sortOrder: (row['sort_order'] as int? ?? 0),
            snoozedUntil: row['snoozed_until']?.toString(),
          )));

    if (settingRows.isNotEmpty) {
      final decoded = <String, dynamic>{};
      for (final entry in settingRows.entries) {
        try {
          decoded[entry.key] = jsonDecode(entry.value);
        } catch (_) {
          decoded[entry.key] = entry.value;
        }
      }
      settings = PlannerSettings.fromJson(decoded);
    }

    groups
      ..clear()
      ..addAll(listRows.map((row) => TaskGroup(
            id: row['id']! as String,
            name: row['name']! as String,
            collapsed: (row['collapsed'] as int? ?? 0) == 1,
          )));

    if (groups.isEmpty) {
      groups.add(TaskGroup(id: _defaultListId, name: 'قائمتي'));
      await _save();
    }
  }

  Future<void> _save() async {
    // Tasks are replaced first because task_lists has a cascading FK.
    await database.replaceTasks(
      tasks.map((task) => <String, Object?>{
        'id': task.id,
        'day_key': task.dayKey,
        'text': task.text,
        'hour': task.hour,
        'minute': task.minute,
        'color_value': task.colorValue,
        'status': task.status.name,
        'repeat_daily': task.repeatDaily ? 1 : 0,
        'repeat_days': _encodeRepeatDays(task.repeatDays),
        'series_id': null,
        'list_id': task.listId,
        'notification_id': task.notificationId,
        'snoozed_until': task.snoozedUntil,
        'sort_order': task.sortOrder,
      }).toList(),
    );
    await database.replaceLists(
      groups.asMap().entries.map((entry) => <String, Object?>{
        'id': entry.value.id,
        'name': entry.value.name,
        'collapsed': entry.value.collapsed ? 1 : 0,
        'sort_order': entry.key,
      }).toList(),
    );

    await database.saveSettings({
      for (final entry in settings.toJson().entries)
        entry.key: jsonEncode(entry.value),
    });
  }

  Future<void> prepareNewDay() async {
    final today = dayKeyOf(DateTime.now());
    final todayDate = DateTime.now();
    final previousRecurring = tasks.where((task) {
      if (task.dayKey == today) return false;
      if (task.repeatDaily) return true;
      return task.repeatDays.contains(todayDate.weekday);
    }).toList();

    final alreadyCreated = tasks.where((task) => task.dayKey == today).toSet();
    for (final old in previousRecurring) {
      final exists = tasks.any((task) =>
          task.dayKey == today &&
          task.text == old.text &&
          task.hour == old.hour &&
          task.minute == old.minute &&
          task.listId == old.listId);
      if (!exists && !alreadyCreated.contains(old)) {
        tasks.add(PlannerTask(
          id: '${DateTime.now().microsecondsSinceEpoch}_${old.id}',
          dayKey: today,
          text: old.text,
          hour: old.hour,
          minute: old.minute,
          colorValue: old.colorValue,
          status: TaskStatus.pending,
          repeatDaily: old.repeatDaily,
          repeatDays: old.repeatDays,
          listId: old.listId,
          sortOrder: old.sortOrder,
        ));
      }
    }
    await _save();
  }

  List<PlannerTask> get todayTasks {
    final key = dayKeyOf(DateTime.now());
    final result = tasks.where((task) => task.dayKey == key).toList();
    result.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      final first = a.hour * 60 + a.minute;
      final second = b.hour * 60 + b.minute;
      return first.compareTo(second);
    });
    return result;
  }

  List<TaskGroup> get activeGroups => List.unmodifiable(groups);

  List<PlannerTask> tasksForGroup(String groupId) =>
      todayTasks.where((task) => task.listId == groupId).toList();

  int remainingForGroup(String groupId) => tasksForGroup(groupId)
      .where((task) => task.status != TaskStatus.done)
      .length;

  Future<void> addGroup(String name) async {
    final clean = name.trim();
    if (clean.isEmpty) return;
    groups.add(TaskGroup(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: clean,
    ));
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> toggleGroup(String groupId) async {
    final group = groups.firstWhere((item) => item.id == groupId);
    group.collapsed = !group.collapsed;
    await _save();
    notifyListeners();
  }

  Future<void> renameGroup(TaskGroup group, String name) async {
    if (name.trim().isEmpty) return;
    group.name = name.trim();
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> deleteGroup(TaskGroup group) async {
    if (groups.length <= 1) return;
    final deletedTasks = tasks.where((item) => item.listId == group.id).toList();
    await NotificationService.cancelForGroup(
      group.id,
      deletedTasks.map((task) => task.notificationId),
    );
    tasks.removeWhere((item) => item.listId == group.id);
    groups.removeWhere((item) => item.id == group.id);
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> reorderGroups(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final group = groups.removeAt(oldIndex);
    groups.insert(newIndex, group);
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> reorderTasks(String groupId, int oldIndex, int newIndex) async {
    final items = tasks.where((task) => task.dayKey == dayKeyOf(DateTime.now()) && task.listId == groupId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (newIndex > oldIndex) newIndex -= 1;
    final task = items.removeAt(oldIndex);
    items.insert(newIndex, task);
    for (var i = 0; i < items.length; i++) items[i].sortOrder = i;
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  List<String> get historyDays {
    return tasks.map((task) => task.dayKey).toSet().toList()
      ..sort((a, b) => b.compareTo(a));
  }

  Future<void> addTask({
    required String text,
    required TimeOfDay time,
    required int color,
    required bool repeatDaily,
    Set<int> repeatDays = const <int>{},
    DateTime? date,
    String listId = _defaultListId,
  }) async {
    if (text.trim().isEmpty) return;
    tasks.add(PlannerTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      dayKey: dayKeyOf(date ?? DateTime.now()),
      text: text.trim(),
      hour: time.hour,
      minute: time.minute,
      colorValue: color,
      repeatDaily: repeatDaily,
      repeatDays: repeatDays,
      listId: listId,
      sortOrder: tasks.where((item) => item.listId == listId && item.dayKey == dayKeyOf(date ?? DateTime.now())).length,
    ));
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> updateTask(
    PlannerTask task, {
    required String text,
    required TimeOfDay time,
    required int color,
    required bool repeatDaily,
    Set<int> repeatDays = const <int>{},
    DateTime? date,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final originalDate = dateFromKey(task.dayKey);
    final isRecurring = task.repeatDaily || task.repeatDays.isNotEmpty;
    if (isRecurring) {
      // Preserve the historical occurrence and put edits on future occurrences only.
      task.repeatDaily = false;
      task.repeatDays = <int>{};
      final nextDate = DateTime(originalDate.year, originalDate.month, originalDate.day + 1);
      tasks.add(PlannerTask(
        id: '${DateTime.now().microsecondsSinceEpoch}_future',
        dayKey: dayKeyOf(date ?? nextDate),
        text: clean,
        hour: time.hour,
        minute: time.minute,
        colorValue: color,
        repeatDaily: repeatDaily,
        repeatDays: {...repeatDays},
        listId: task.listId,
        sortOrder: task.sortOrder,
      ));
    } else {
      task
        ..text = clean
        ..hour = time.hour
        ..minute = time.minute
        ..colorValue = color
        ..repeatDaily = repeatDaily
        ..repeatDays = {...repeatDays}
        ..dayKey = dayKeyOf(date ?? originalDate);
    }
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> updateRepeatDays(PlannerTask task, Set<int> days) async {
    task.repeatDays = {...days};
    task.repeatDaily = false;
    if (task.repeatDays.isEmpty) tasks.removeWhere((item) => item.id == task.id);
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> snoozeTask(String taskId, String dayKey, DateTime until) async {
    PlannerTask? task;
    for (final candidate in tasks) {
      if (candidate.id == taskId && candidate.dayKey == dayKey) {
        task = candidate;
        break;
      }
    }
    if (task == null || task.status != TaskStatus.pending) return;
    task.snoozedUntil = until.toIso8601String();
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> setStatus(PlannerTask task, TaskStatus status) async {
    task.status = status;
    task.snoozedUntil = null;
    if (status != TaskStatus.pending) {
      await NotificationService.plugin.cancel(task.notificationId);
    }
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> deleteTask(PlannerTask task) async {
    await NotificationService.plugin.cancel(task.notificationId);
    tasks.removeWhere((item) => item.id == task.id);
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> saveSettings() async {
    await _save();
    notifyListeners();
    await NotificationService.refresh(this);
  }

  Future<void> reloadFromBackground() async {
    await load();
    notifyListeners();
  }

  List<PlannerTask> tasksForDay(String key) =>
      tasks.where((task) => task.dayKey == key).toList()
        ..sort((a, b) => (a.hour * 60 + a.minute)
            .compareTo(b.hour * 60 + b.minute));
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();
  static String? _pendingCustomPayload;

  static String? takeCustomPayload() {
    final value = _pendingCustomPayload;
    _pendingCustomPayload = null;
    return value;
  }
  static const String groupKeyPrefix = 'injaz_group_';

  static int _summaryId(String listId, String dayKey) {
    var hash = 23;
    for (final unit in '$listId|$dayKey'.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return 900000000 + (hash % 90000000);
  }

  static String _groupKey(String listId, String dayKey) =>
      '$groupKeyPrefix${listId}_$dayKey';

  static Future<void> initialize() async {
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Aden'));
    }

    const android = AndroidInitializationSettings('ic_notification');
    const settings = InitializationSettings(android: android);
    await plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleForegroundResponse,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    final androidPlugin =
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  static Future<void> _handleForegroundResponse(
      NotificationResponse response) async {
    if (response.actionId == 'later_custom') {
      _pendingCustomPayload = response.payload;
      return;
    }
    await notificationTapBackground(response);
  }

  static String _groupBody(List<PlannerTask> pending, bool english) {
    final lines = pending
        .map((task) => '${task.timeLabelFor(english)}  ${task.text.replaceAll('\n', ' ')}')
        .join('\n');
    return lines.length > 3000 ? '${lines.substring(0, 3000)}…' : lines;
  }

  static AndroidNotificationDetails _summaryDetails(
    bool english,
    String groupKey,
    String body,
  ) =>
      AndroidNotificationDetails(
        'injaz_list_summary_channel',
        english ? 'Task list reminders' : 'تذكيرات قوائم المهام',
        channelDescription: english
            ? 'One grouped reminder for each task list'
            : 'إشعار مجمع لكل قائمة مهام',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        ongoing: true,
        autoCancel: false,
        groupKey: groupKey,
        setAsGroupSummary: true,
        styleInformation: BigTextStyleInformation(body),
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'open_list',
            english ? 'View more' : 'عرض المزيد',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      );

  static AndroidNotificationDetails _taskDetails(
    bool english,
    String groupKey,
  ) =>
      AndroidNotificationDetails(
        'injaz_list_tasks_channel',
        english ? 'Tasks in a list' : 'مهام القائمة',
        channelDescription: english
            ? 'Task actions grouped under each list'
            : 'إجراءات المهام ضمن كل قائمة',
        importance: Importance.max,
        priority: Priority.max,
        playSound: false,
        ongoing: true,
        autoCancel: false,
        groupKey: groupKey,
        actions: <AndroidNotificationAction>[
          AndroidNotificationAction(
            'done',
            english ? 'Done' : 'تم',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'not_done',
            english ? 'Not done' : 'لم يتم',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'later_1h',
            english ? 'Later 1h' : 'لاحقاً ساعة',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'later_tomorrow',
            english ? 'Tomorrow 00:00' : 'غداً 00:00',
            showsUserInterface: false,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            'later_custom',
            english ? 'Custom time' : 'وقت مخصص',
            showsUserInterface: true,
            cancelNotification: false,
          ),
        ],
      );

  static Future<void> cancelForGroup(
    String groupId,
    Iterable<int> taskNotificationIds,
  ) async {
    for (final notificationId in taskNotificationIds) {
      await plugin.cancel(notificationId);
    }
    await plugin.cancel(_summaryId(groupId, dayKeyOf(DateTime.now())));
  }

  static Future<void> refresh(PlannerController controller) async {
    final today = dayKeyOf(DateTime.now());
    final knownIds = <int>{
      for (final task in controller.tasks) task.notificationId,
      for (final group in controller.groups) _summaryId(group.id, today),
    };
    for (final id in knownIds) await plugin.cancel(id);
    if (!controller.settings.notificationsEnabled) return;

    final now = tz.TZDateTime.now(tz.local);
    final english = controller.settings.english;

    for (final group in controller.groups) {
      final pending = controller.tasksForGroup(group.id)
          .where((task) => task.status == TaskStatus.pending && (task.snoozedUntil == null || DateTime.tryParse(task.snoozedUntil!)?.isBefore(DateTime.now()) != false))
          .toList()
        ..sort((a, b) =>
            (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      if (pending.isEmpty) continue;

      // Each task receives its own real scheduled time; never use the first task's time.
      final first = pending.first;
      var summaryTrigger = tz.TZDateTime(tz.local, now.year, now.month, now.day, first.hour, first.minute);
      if (summaryTrigger.isBefore(now)) summaryTrigger = now.add(const Duration(seconds: 2));

      final key = _groupKey(group.id, today);
      final summaryId = _summaryId(group.id, today);
      final summaryDetails = NotificationDetails(
        android: _summaryDetails(english, key, _groupBody(pending, english)),
      );
      final summaryPayload = jsonEncode({
        'listId': group.id,
        'dayKey': today,
        'summary': true,
      });

      final taskDetails = NotificationDetails(
        android: _taskDetails(english, key),
      );

      if (!summaryTrigger.isAfter(now.add(const Duration(seconds: 3)))) {
        await plugin.show(
          summaryId,
          group.name,
          _groupBody(pending, english),
          summaryDetails,
          payload: summaryPayload,
        );
        for (final task in pending) {
          await plugin.show(
            task.notificationId,
            task.text.replaceAll('\n', ' '),
            '${group.name} • ${task.timeLabelFor(english)}',
            taskDetails,
            payload: jsonEncode({
              'taskId': task.id,
              'dayKey': task.dayKey,
              'listId': group.id,
            }),
          );
        }
      } else {
        try {
          await plugin.zonedSchedule(
            summaryId,
            group.name,
            _groupBody(pending, english),
            summaryTrigger,
            summaryDetails,
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            payload: summaryPayload,
          );
          for (final task in pending) {
            await plugin.zonedSchedule(
              task.notificationId,
              task.text.replaceAll('\n', ' '),
              '${group.name} • ${task.timeLabelFor(english)}',
              (() { final t = tz.TZDateTime(tz.local, now.year, now.month, now.day, task.hour, task.minute); return t.isBefore(now) ? now.add(const Duration(seconds: 2)) : t; })(),
              taskDetails,
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              payload: jsonEncode({
                'taskId': task.id,
                'dayKey': task.dayKey,
                'listId': group.id,
              }),
            );
          }
        } catch (_) {
          await plugin.zonedSchedule(
            summaryId,
            group.name,
            _groupBody(pending, english),
            summaryTrigger,
            summaryDetails,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            payload: summaryPayload,
          );
          for (final task in pending) {
            await plugin.zonedSchedule(
              task.notificationId,
              task.text.replaceAll('\n', ' '),
              '${group.name} • ${task.timeLabelFor(english)}',
              (() { final t = tz.TZDateTime(tz.local, now.year, now.month, now.day, task.hour, task.minute); return t.isBefore(now) ? now.add(const Duration(seconds: 2)) : t; })(),
              taskDetails,
              androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
              payload: jsonEncode({
                'taskId': task.id,
                'dayKey': task.dayKey,
                'listId': group.id,
              }),
            );
          }
        }
      }
    }
    await _scheduleDailyReport(controller, now);
  }

  static int _reportId = 991234567;
  static Future<void> _scheduleDailyReport(PlannerController controller, tz.TZDateTime now) async {
    await plugin.cancel(_reportId);
    if (!controller.settings.dailyReportEnabled || !controller.settings.notificationsEnabled) return;
    final reportTime = tz.TZDateTime(tz.local, now.year, now.month, now.day,
      controller.settings.dailyReportHour, controller.settings.dailyReportMinute);
    final trigger = reportTime.isAfter(now) ? reportTime : reportTime.add(const Duration(days: 1));
    final today = dayKeyOf(DateTime.now());
    final tasks = controller.tasksForDay(today);
    final done = tasks.where((t) => t.status == TaskStatus.done).length;
    final notDone = tasks.where((t) => t.status == TaskStatus.notDone).length;
    final pending = tasks.where((t) => t.status == TaskStatus.pending).length;
    final body = controller.groups.map((g) {
      final list = tasks.where((t) => t.listId == g.id).toList();
      final d = list.where((t) => t.status == TaskStatus.done).length;
      final n = list.where((t) => t.status == TaskStatus.notDone).length;
      final q = list.where((t) => t.status == TaskStatus.pending).length;
      return '${g.name}: done=$d, notDone=$n, pending=$q';
    }).join('\n');
    final details = NotificationDetails(android: AndroidNotificationDetails(
      'injaz_daily_report_channel', controller.settings.english ? 'Daily reports' : 'التقرير اليومي',
      channelDescription: controller.settings.english ? 'Independent daily task report' : 'تقرير يومي مستقل عن إشعارات المهام',
      importance: Importance.defaultImportance, priority: Priority.defaultPriority,
      styleInformation: BigTextStyleInformation('done=$done, notDone=$notDone, pending=$pending\n$body'),
    ));
    await plugin.zonedSchedule(_reportId, controller.settings.english ? 'Daily report' : 'التقرير اليومي',
      'done=$done, notDone=$notDone, pending=$pending\n$body', trigger, details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle);
  }
}

@pragma('vm:entry-point')
Future<void> notificationTapBackground(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();
  try { tz.setLocalLocation(tz.getLocation('UTC')); } catch (_) {}

  if (response.actionId != 'done' &&
      response.actionId != 'not_done' &&
      response.actionId != 'later_1h' &&
      response.actionId != 'later_tomorrow' &&
      response.actionId != 'later_custom') {
    return;
  }

  Map<String, dynamic> payload;
  try {
    payload = jsonDecode(response.payload ?? '')
        as Map<String, dynamic>;
  } catch (_) {
    return;
  }

  final taskId = payload['taskId'] as String?;
  final dayKey = payload['dayKey'] as String?;
  final listId = payload['listId'] as String?;

  if (taskId == null || dayKey == null || listId == null) {
    return;
  }

  final database = await AppDatabase.open();
  if (response.actionId == 'later_custom') {
    _pendingCustomPayload = response.payload;
    await database.close();
    return;
  }
  if (response.actionId == 'later_1h' || response.actionId == 'later_tomorrow') {
    final now = DateTime.now();
    final untilDate = response.actionId == 'later_1h'
        ? now.add(const Duration(hours: 1))
        : DateTime(now.year, now.month, now.day + 1);
    final until = untilDate.toIso8601String();
    await database.db.update('tasks', <String, Object?>{'snoozed_until': until}, where: 'id = ? AND day_key = ?', whereArgs: <Object?>[taskId, dayKey]);
    final task = await database.db.query('tasks', where: 'id = ? AND day_key = ?', whereArgs: <Object?>[taskId, dayKey], limit: 1);
    if (task.isNotEmpty) {
      final row = task.first;
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('ic_notification')));
      final when = tz.TZDateTime.from(DateTime.parse(until), tz.local);
      await plugin.zonedSchedule(PlannerTask(id: taskId, dayKey: dayKey, text: '', hour: 0, minute: 0, colorValue: _purple.value).notificationId,
        row['text']?.toString() ?? '', 'إنجاز', when,
        const NotificationDetails(android: AndroidNotificationDetails('injaz_list_tasks_channel', 'مهام القائمة', importance: Importance.max, priority: Priority.max)),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({'taskId': taskId, 'dayKey': dayKey, 'listId': listId}));
    }
    await database.close();
    return;
  }
  final newStatus = response.actionId == 'done'
      ? TaskStatus.done.name
      : TaskStatus.notDone.name;

  await database.db.update(
    'tasks',
    <String, Object?>{'status': newStatus},
    where: 'id = ? AND day_key = ?',
    whereArgs: <Object?>[taskId, dayKey],
  );

  final taskRows = await database.db.query(
    'tasks',
    where: 'day_key = ? AND list_id = ?',
    whereArgs: <Object?>[dayKey, listId],
    orderBy: 'hour ASC, minute ASC, rowid ASC',
  );

  final listRows = await database.db.query(
    'task_lists',
    where: 'id = ?',
    whereArgs: <Object?>[listId],
    limit: 1,
  );

  final groupName = listRows.isEmpty
      ? 'قائمة المهام'
      : listRows.first['name'] as String;

  final pending = taskRows
      .where((row) => row['status'] == TaskStatus.pending.name)
      .map((row) => PlannerTask(
            id: row['id']! as String,
            dayKey: row['day_key']! as String,
            text: row['text']! as String,
            hour: row['hour']! as int,
            minute: row['minute']! as int,
            colorValue: row['color_value']! as int,
            status: TaskStatus.pending,
            repeatDaily: (row['repeat_daily'] as int? ?? 0) == 1,
            repeatDays: _decodeRepeatDays(row['repeat_days']?.toString() ?? ''),
            listId: row['list_id']! as String,
            sortOrder: (row['sort_order'] as int? ?? 0),
          ))
      .toList();

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    ),
  );

  final changedId = PlannerTask(
    id: taskId,
    dayKey: dayKey,
    text: '',
    hour: 0,
    minute: 0,
    colorValue: _purple.value,
  ).notificationId;
  await notifications.cancel(changedId);

  var hash = 23;
  for (final unit in '$listId|$dayKey'.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }

  final summaryId = 900000000 + (hash % 90000000);
  if (pending.isEmpty) {
    await notifications.cancel(summaryId);
    for (final row in taskRows) {
      final id = row['id']! as String;
      await notifications.cancel(
        PlannerTask(
          id: id,
          dayKey: row['day_key']! as String,
          text: '',
          hour: 0,
          minute: 0,
          colorValue: _purple.value,
        ).notificationId,
      );
    }
    return;
  }

  final settingRows = await database.getSettings();
  final englishValue = settingRows['english'];
  final english = englishValue == null
      ? false
      : jsonDecode(englishValue) == true;
  final groupKey = 'injaz_group_${listId}_$dayKey';
  final body = pending
      .map((task) =>
          '${task.timeLabelFor(english)}  ${task.text.replaceAll('\n', ' ')}')
      .join('\n');

  await notifications.show(
    summaryId,
    groupName,
    body.length > 3000 ? '${body.substring(0, 3000)}…' : body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'injaz_list_summary_channel',
        english ? 'Task list reminders' : 'تذكيرات قوائم المهام',
        channelDescription: english
            ? 'One grouped reminder for each task list'
            : 'إشعار مجمع لكل قائمة مهام',
        importance: Importance.max,
        priority: Priority.max,
        ongoing: true,
        autoCancel: false,
        groupKey: groupKey,
        setAsGroupSummary: true,
        styleInformation: BigTextStyleInformation(body),
      ),
    ),
    payload: jsonEncode({
      'listId': listId,
      'dayKey': dayKey,
      'summary': true,
    }),
  );
}

class InjazApp extends StatelessWidget {
  const InjazApp({super.key, required this.controller});
  final PlannerController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final dark = controller.settings.darkMode;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Injaz',
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _purple,
              brightness: Brightness.light,
            ),
            scaffoldBackgroundColor: const Color(0xFFF8F7FB),
            cardTheme: CardThemeData(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(
              seedColor: _purple,
              brightness: Brightness.dark,
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          home: PlannerHome(controller: controller),
        );
      },
    );
  }
}

class PlannerHome extends StatefulWidget {
  const PlannerHome({super.key, required this.controller});
  final PlannerController controller;

  @override
  State<PlannerHome> createState() => _PlannerHomeState();
}

class _PlannerHomeState extends State<PlannerHome> with WidgetsBindingObserver {
  int selectedTab = 0;
  final Map<String, TextEditingController> _inlineControllers = {};
  final Map<String, FocusNode> _inlineFocusNodes = {};
  final Map<String, TimeOfDay> _inlineTimes = {};
  final Map<String, bool> _inlineRepeats = {};
  final Map<String, Set<int>> _inlineRepeatDays = {};
  final Map<String, DateTime> _inlineDates = {};
  final Map<String, int> _inlineColors = {};
  final Set<String> _addingForGroup = {};
  PlannerController get c => widget.controller;
  bool get en => c.settings.english;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _inlineControllers.values) {
      controller.dispose();
    }
    for (final node in _inlineFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.reloadFromBackground().then((_) async {
        await NotificationService.refresh(c);
        final payload = NotificationService.takeCustomPayload();
        if (payload != null && mounted) {
          await _showCustomSnooze(payload);
        }
      });
    }
  }

  String tr(String ar, String english) => en ? english : ar;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _homePage(),
      _historyPage(),
      _statisticsPage(),
      _settingsPage(),
    ];
    return Directionality(
      textDirection: en ? TextDirection.ltr : TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(tr('إنجاز', 'Injaz'),
              style: const TextStyle(fontWeight: FontWeight.w800)),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 16),
              child: Center(
                child: Text(
                  _shortDate(DateTime.now(), en),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
        body: IndexedStack(index: selectedTab, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedTab,
          onDestinationSelected: (value) =>
              setState(() => selectedTab = value),
          destinations: [
            NavigationDestination(
                icon: const Icon(Icons.checklist_rounded),
                label: tr('الرئيسية', 'Home')),
            NavigationDestination(
                icon: const Icon(Icons.history_rounded),
                label: tr('السجل', 'History')),
            NavigationDestination(
                icon: const Icon(Icons.bar_chart_rounded),
                label: tr('الإحصائيات', 'Stats')),
            NavigationDestination(
                icon: const Icon(Icons.settings_rounded),
                label: tr('الإعدادات', 'Settings')),
          ],
        ),
      ),
    );
  }

  String _shortDate(DateTime date, bool english) {
    final months = english
        ? ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
        : ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    return '${date.day} ${months[date.month - 1]}';
  }

  Widget _homePage() {
    final tasks = c.todayTasks;
    final total = tasks.length;
    final remaining =
        tasks.where((task) => task.status != TaskStatus.done).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: _counterCard(
                tr('كل المهام', 'All tasks'),
                total,
                Icons.checklist_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _counterCard(
                tr('المتبقية', 'Remaining'),
                remaining,
                Icons.hourglass_bottom_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Text(
                tr('قوائم مهامي', 'My lists'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: _createGroup,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: Text(tr('قائمة جديدة', 'New list')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (c.groups.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Text(tr('أنشئ قائمتك الأولى للبدء.', 'Create your first list to begin.')),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: c.groups.length,
            onReorder: c.reorderGroups,
            itemBuilder: (context, index) => _groupCard(c.groups[index]),
          ),
      ],
    );
  }

  Widget _counterCard(String label, int value, IconData icon) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Icon(icon, color: _purple, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupCard(TaskGroup group) {
    final items = c.tasksForGroup(group.id);
    final pending = items.where((t) => t.status != TaskStatus.done).length;
    final isCompleted = items.isNotEmpty && items.every((task) => task.status == TaskStatus.done);
    return Card(
      key: ValueKey(group.id),
      color: isCompleted ? Colors.green.withValues(alpha: .10) : null,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => c.toggleGroup(group.id),
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(14, 13, 8, 13),
              child: Row(
                children: [
                  Icon(
                    group.collapsed
                        ? Icons.folder_outlined
                        : Icons.folder_open_rounded,
                    color: isCompleted ? Colors.green : _purple,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: TextStyle(fontWeight: FontWeight.w800, color: isCompleted ? Colors.green.shade700 : null),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$pending ${tr('متبقية من', 'remaining of')} ${items.length} ${tr('مهام', 'tasks')}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'rename') _renameGroup(group);
                      if (value == 'delete') _deleteGroup(group);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(tr('إعادة تسمية', 'Rename')),
                      ),
                      if (c.groups.length > 1)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(tr('حذف القائمة', 'Delete list')),
                        ),
                    ],
                  ),
                  if (isCompleted) ...[
                    const Icon(Icons.verified_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 4),
                  ],
                  Icon(
                    group.collapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                  ),
                ],
              ),
            ),
          ),
          if (!group.collapsed) ...[
            const Divider(height: 1),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  tr('لا توجد مهام في هذه القائمة بعد.', 'No tasks in this list yet.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              )
            else
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                onReorder: (oldIndex, newIndex) => c.reorderTasks(group.id, oldIndex, newIndex),
                itemBuilder: (context, index) => _taskCard(items[index]),
              ),
            if (_addingForGroup.contains(group.id))
              _inlineTaskComposer(group),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _startInlineAdd(group),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(tr('إضافة مهمة هنا', 'Add task here')),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _startInlineAdd(TaskGroup group) {
    if (!_addingForGroup.contains(group.id)) {
      _inlineControllers[group.id] = TextEditingController();
      _inlineFocusNodes[group.id] = FocusNode();
      _inlineTimes[group.id] = const TimeOfDay(hour: 9, minute: 0);
      _inlineRepeats[group.id] = false;
      _inlineRepeatDays[group.id] = <int>{};
      _inlineDates[group.id] = DateTime.now();
      _inlineColors[group.id] = _purple.value;
      _addingForGroup.add(group.id);
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inlineFocusNodes[group.id]?.requestFocus();
    });
  }

  Widget _inlineTaskComposer(TaskGroup group) {
    final controller = _inlineControllers[group.id]!;
    final focusNode = _inlineFocusNodes[group.id]!;
    final time = _inlineTimes[group.id] ?? const TimeOfDay(hour: 9, minute: 0);
    final repeat = _inlineRepeats[group.id] ?? false;
    final repeatDays = _inlineRepeatDays[group.id] ?? <int>{};
    final date = _inlineDates[group.id] ?? DateTime.now();
    final color = _inlineColors[group.id] ?? _purple.value;
    const palette = <int>[
      0xFF6750A4, 0xFF287A72, 0xFF3478C8, 0xFFE18A32,
      0xFFD45C78, 0xFF607D8B, 0xFF7B8D35,
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _purple.withValues(alpha: .35)),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: true,
            minLines: 1,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: tr('اكتب المهمة الجديدة...', 'Write a new task...'),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: time,
                    builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        alwaysUse24HourFormat: false,
                      ),
                      child: child!,
                    ),
                  );
                  if (picked != null) {
                    setState(() => _inlineTimes[group.id] = picked);
                  }
                },
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(_formatTwelveHour(context, time)),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(context: context, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (picked != null) setState(() => _inlineDates[group.id] = picked);
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 17),
                label: Text('${date.day}/${date.month}'),
              ),
              IconButton(
                tooltip: tr('تغيير اللون', 'Change color'),
                onPressed: () {
                  final current = palette.indexOf(color);
                  setState(() => _inlineColors[group.id] =
                      palette[(current + 1) % palette.length]);
                },
                icon: Icon(Icons.circle, color: Color(color), size: 20),
              ),
              const Spacer(),
            ],
          ),
          Row(
            children: [
              Checkbox(
                value: repeat,
                onChanged: (value) => setState(
                  () => _inlineRepeats[group.id] = value ?? false,
                ),
                visualDensity: VisualDensity.compact,
              ),
              Text(tr('تكرار يومي', 'Daily'), style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              if (!repeat) ...[
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                    label: Text(['ن','ث','ر','خ','ج','س','ح'][day - 1]),
                    selected: repeatDays.contains(day),
                    onSelected: (selected) => setState(() {
                      final next = {...repeatDays};
                      selected ? next.add(day) : next.remove(day);
                      _inlineRepeatDays[group.id] = next;
                    }),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
              TextButton(
                onPressed: () {
                  setState(() {
                    _addingForGroup.remove(group.id);
                    _inlineControllers.remove(group.id)?.dispose();
                    _inlineFocusNodes.remove(group.id)?.dispose();
                    _inlineTimes.remove(group.id);
                    _inlineRepeats.remove(group.id);
                    _inlineRepeatDays.remove(group.id);
                    _inlineDates.remove(group.id);
                    _inlineColors.remove(group.id);
                  });
                },
                child: Text(tr('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () => _submitInlineTask(group),
                child: Text(tr('حفظ', 'Save')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTwelveHour(BuildContext context, TimeOfDay time) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      time,
      alwaysUse24HourFormat: false,
    );
  }

  Future<void> _submitInlineTask(TaskGroup group) async {
    final controller = _inlineControllers[group.id];
    if (controller == null || controller.text.trim().isEmpty) return;
    await c.addTask(
      text: controller.text,
      time: _inlineTimes[group.id] ?? const TimeOfDay(hour: 9, minute: 0),
      color: _inlineColors[group.id] ?? _purple.value,
      repeatDaily: _inlineRepeats[group.id] ?? false,
      repeatDays: _inlineRepeatDays[group.id] ?? <int>{},
      date: _inlineDates[group.id],
      listId: group.id,
    );
    controller.clear();
    if (mounted) {
      _inlineFocusNodes[group.id]?.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('تمت إضافة المهمة. يمكنك كتابة المهمة التالية.', 'Task added. You can enter the next one.')),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _createGroup() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('قائمة جديدة', 'New list')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: tr('اسم القائمة', 'List name'),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(tr('إنشاء', 'Create')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await c.addGroup(name);
  }

  Future<void> _renameGroup(TaskGroup group) async {
    final controller = TextEditingController(text: group.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('إعادة تسمية القائمة', 'Rename list')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('اسم القائمة', 'List name')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(tr('حفظ', 'Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null) await c.renameGroup(group, name);
  }

  Future<void> _deleteGroup(TaskGroup group) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('حذف القائمة؟', 'Delete list?')),
        content: Text(tr(
          'سيتم حذف القائمة وجميع المهام الموجودة داخلها نهائياً.',
          'The list and all tasks inside it will be permanently deleted.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (yes == true) await c.deleteGroup(group);
  }

  Widget _taskCard(PlannerTask task) {
    final color = Color(task.colorValue);
    final isDone = task.status == TaskStatus.done;
    final isNotDone = task.status == TaskStatus.notDone;
    final card = Container(
      margin: const EdgeInsets.fromLTRB(10, 7, 10, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _openTaskEditor(task),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task.text,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: isDone ? TextDecoration.lineThrough : null,
                      color: isDone
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.access_time_rounded, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        _formatTwelveHour(
                          context,
                          TimeOfDay(hour: task.hour, minute: task.minute),
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (task.repeatDaily) ...[
                        const SizedBox(width: 8),
                        const Icon(Icons.repeat_rounded, size: 13),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _taskStatusButton(
                label: tr('تم', 'Done'),
                icon: Icons.check_rounded,
                selected: isDone,
                onPressed: () => c.setStatus(task, TaskStatus.done),
              ),
              const SizedBox(height: 5),
              _taskStatusButton(
                label: tr('لم يتم', 'Not done'),
                icon: Icons.close_rounded,
                selected: isNotDone,
                onPressed: () => c.setStatus(task, TaskStatus.notDone),
              ),
            ],
          ),
        ],
      ),
    );
    return KeyedSubtree(
      key: ValueKey(task.id),
      child: GestureDetector(
        onLongPress: () => _confirmDelete(task),
        child: card,
      ),
    );
  }

  Widget _taskStatusButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        color: selected ? (icon == Icons.check_rounded ? Colors.green : Colors.red) : null,
        style: IconButton.styleFrom(
          backgroundColor: selected ? (icon == Icons.check_rounded ? Colors.green.withValues(alpha: .14) : Colors.red.withValues(alpha: .14)) : null,
          minimumSize: const Size(38, 34),
        ),
      ),
    );
  }

  Future<void> _openTaskEditor(PlannerTask task) async {
    final textController = TextEditingController(text: task.text);
    TimeOfDay time = TimeOfDay(hour: task.hour, minute: task.minute);
    int color = task.colorValue;
    bool repeat = task.repeatDaily;
    DateTime selectedDate = dateFromKey(task.dayKey);
    Set<int> repeatDays = {...task.repeatDays};
    final colors = <Color>[
      const Color(0xFF6750A4),
      const Color(0xFF287A72),
      const Color(0xFF3478C8),
      const Color(0xFFE18A32),
      const Color(0xFFD45C78),
      const Color(0xFF607D8B),
      const Color(0xFF7B8D35),
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr('تعديل المهمة', 'Edit task'),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: textController,
                      autofocus: true,
                      minLines: 2,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: tr('اكتب المهمة هنا...', 'Write your task here...'),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16)),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today_outlined),
                      title: Text(tr('تاريخ المهمة', 'Task date')),
                      trailing: Text('${selectedDate.day}/${selectedDate.month}/${selectedDate.year}'),
                      onTap: () async {
                        final picked = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime(2100));
                        if (picked != null) setSheetState(() => selectedDate = picked);
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time_rounded),
                      title: Text(tr('وقت البداية', 'Start time')),
                      trailing: Text(time.format(context),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      onTap: () async {
                        final picked = await showTimePicker(
                            context: context, initialTime: time);
                        if (picked != null) setSheetState(() => time = picked);
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(tr('لون المهمة', 'Task color'),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: colors.map((item) {
                        return InkWell(
                          onTap: () => setSheetState(() => color = item.value),
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: item,
                              shape: BoxShape.circle,
                              border: color == item.value
                                  ? Border.all(
                                      color: Theme.of(context).colorScheme.onSurface,
                                      width: 3)
                                  : null,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: repeat,
                      onChanged: (value) => setSheetState(() => repeat = value),
                      title: Text(tr('تكرار يومي', 'Repeat daily')),
                      subtitle: Text(tr('إنشاء نسخة جديدة غداً لهذه المهمة.',
                          'Create a fresh copy of this task tomorrow.')),
                    ),
                    if (!repeat) ...[
                      const SizedBox(height: 4),
                      Text(tr('أيام التكرار الأسبوعي', 'Weekly repeat days'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      Wrap(spacing: 6, children: [
                        for (var day = 1; day <= 7; day++) FilterChip(
                          label: Text(['ن','ث','ر','خ','ج','س','ح'][day - 1]),
                          selected: repeatDays.contains(day),
                          onSelected: (selected) => setSheetState(() { selected ? repeatDays.add(day) : repeatDays.remove(day); }),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () async {
                          if (textController.text.trim().isEmpty) return;
                          await c.updateTask(
                            task,
                            text: textController.text,
                            time: time,
                            color: color,
                            repeatDaily: repeat,
                            repeatDays: repeatDays,
                            date: selectedDate,
                          );
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                        },
                        child: Text(tr('حفظ المهمة', 'Save task')),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    textController.dispose();
  }

  Future<void> _confirmDelete(PlannerTask task) async {
    final recurring = task.repeatDaily || task.repeatDays.isNotEmpty;
    final selected = {...(task.repeatDaily ? <int>{1, 2, 3, 4, 5, 6, 7} : task.repeatDays)};
    final result = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(tr('حذف المهمة؟', 'Delete task?')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(recurring ? tr('هذه مهمة متكررة. اختر أيام التكرار التي تريد إزالتها:', 'This task repeats. Choose the repeat days to remove:') : tr('لن يمكن استعادة هذه المهمة بعد حذفها.', 'This task cannot be restored after deletion.')),
              if (recurring) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 4, children: [for (var day = 1; day <= 7; day++) FilterChip(
                  label: Text(['ن','ث','ر','خ','ج','س','ح'][day - 1]),
                  selected: selected.contains(day),
                  onSelected: (value) => setState(() => value ? selected.add(day) : selected.remove(day)),
                )]),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, recurring ? selected : const <int>{}), child: Text(tr('حذف', 'Delete'))),
          ],
        ),
      ),
    );
    if (result is Set<int>) {
      if (recurring && result.isNotEmpty) {
        await c.updateRepeatDays(task, result);
      } else {
        await c.deleteTask(task);
      }
    }
  }

  Widget _historyPage() {
    final today = DateTime.now();
    final days = {...c.historyDays, dayKeyOf(today), dayKeyOf(today.add(const Duration(days: 1))), dayKeyOf(today.add(const Duration(days: 2)))}.toList()..sort((a, b) => b.compareTo(a));
    if (days.isEmpty) {
      return Center(child: Text(tr('لا يوجد سجل سابق بعد.', 'No history yet.')));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: days.map((key) {
        final date = dateFromKey(key);
        final dayTasks = c.tasksForDay(key);
        final done = dayTasks.where((task) => task.status == TaskStatus.done).length;
        return Card(
          child: ExpansionTile(
            title: Text(formatDate(date, en),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('$done / ${dayTasks.length} ${tr('مكتملة', 'completed')}'),
            children: dayTasks.isEmpty
                ? [ListTile(title: Text(tr('لا توجد مهام', 'No tasks')))]
                : dayTasks
                    .map((task) => ListTile(
                          leading: Icon(
                            task.status == TaskStatus.done
                                ? Icons.check_circle
                                : task.status == TaskStatus.notDone
                                    ? Icons.cancel_outlined
                                    : Icons.radio_button_unchecked,
                            color: Color(task.colorValue),
                          ),
                          title: Text(task.text),
                          subtitle: Text(_formatTwelveHour(context, TimeOfDay(hour: task.hour, minute: task.minute))),
                          trailing: Text(_statusLabel(task.status)),
                        ))
                    .toList(),
          ),
        );
      }).toList(),
    );
  }

  String _statusLabel(TaskStatus status) {
    switch (status) {
      case TaskStatus.done:
        return tr('تم', 'Done');
      case TaskStatus.notDone:
        return tr('لم يتم', 'Not done');
      case TaskStatus.pending:
        return tr('لم تُحدد', 'Not set');
    }
  }

  Widget _statisticsPage() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    final days = List.generate(7, (i) => start.add(Duration(days: i)));
    var total = 0;
    var done = 0;
    final bars = <Widget>[];
    for (final day in days) {
      final items = c.tasksForDay(dayKeyOf(day));
      final completed = items.where((t) => t.status == TaskStatus.done).length;
      total += items.length;
      done += completed;
      final ratio = items.isEmpty ? 0.0 : completed / items.length;
      bars.add(Expanded(
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: ratio == 0 ? .025 : ratio,
                  child: Container(
                    width: 22,
                    decoration: BoxDecoration(
                      color: _purple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(en
                ? ['M', 'T', 'W', 'T', 'F', 'S', 'S'][day.weekday - 1]
                : ['ن', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'][day.weekday - 1]),
          ],
        ),
      ));
    }
    final ratio = total == 0 ? 0.0 : done / total;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('إحصائيات هذا الأسبوع', 'This week'),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 18),
                SizedBox(height: 150, child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: bars)),
                const SizedBox(height: 18),
                Text('${(ratio * 100).round()}% ${tr('نسبة الإنجاز', 'completion rate')}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: ratio, minHeight: 8),
                const SizedBox(height: 12),
                Text('$done ${tr('مكتملة من أصل', 'completed out of')} $total ${tr('مهمة', 'tasks')}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.dark_mode_outlined),
                title: Text(tr('الوضع الداكن', 'Dark mode')),
                value: c.settings.darkMode,
                onChanged: (value) {
                  c.settings.darkMode = value;
                  c.saveSettings();
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.language_rounded),
                title: Text(tr('اللغة الإنجليزية', 'English language')),
                subtitle: Text(tr('إيقاف الخيار يعيد العربية.', 'Turn off to use Arabic.')),
                value: c.settings.english,
                onChanged: (value) {
                  c.settings.english = value;
                  c.saveSettings();
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_active_outlined),
                title: Text(tr('إشعارات القوائم', 'Task list notifications')),
                value: c.settings.notificationsEnabled,
                onChanged: (value) {
                  c.settings.notificationsEnabled = value;
                  c.saveSettings();
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.summarize_outlined),
                title: Text(tr('التقرير اليومي', 'Daily report')),
                subtitle: Text(tr('مستقل عن إشعارات المهام ويعرض done/notDone/pending لكل قائمة.', 'Independent report with done/notDone/pending per list.')),
                value: c.settings.dailyReportEnabled,
                onChanged: (value) { c.settings.dailyReportEnabled = value; c.saveSettings(); },
              ),
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: Text(tr('وقت التقرير اليومي', 'Daily report time')),
                trailing: Text(TimeOfDay(hour: c.settings.dailyReportHour, minute: c.settings.dailyReportMinute).format(context)),
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: TimeOfDay(hour: c.settings.dailyReportHour, minute: c.settings.dailyReportMinute));
                  if (picked != null) { c.settings.dailyReportHour = picked.hour; c.settings.dailyReportMinute = picked.minute; c.saveSettings(); }
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: Text(tr('موعد إشعار القائمة', 'List notification time')),
                subtitle: Text(tr(
                  'يُحدد تلقائياً حسب أقرب مهمة متبقية في كل قائمة.',
                  'Automatically uses the earliest pending task in each list.',
                )),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.copy_all_rounded),
            title: Text(tr('نسخ قائمة مهام اليوم', 'Copy today tasks')),
            subtitle: Text(tr('نسخ المهام وأوقاتها وحالاتها.', 'Copy tasks, times and statuses.')),
            onTap: _copyToday,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(tr('حول التطبيق', 'About')),
            subtitle: Text(tr('تطبيق لتنظيم المهام اليومية دون إنترنت.',
                'An offline daily task planner.')),
          ),
        ),
      ],
    );
  }

  Future<void> _showCustomSnooze(String rawPayload) async {
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(rawPayload) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final taskId = payload['taskId'] as String?;
    final dayKey = payload['dayKey'] as String?;
    if (taskId == null || dayKey == null) return;

    final initial = DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    final until = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!until.isAfter(DateTime.now())) return;
    await c.snoozeTask(taskId, dayKey, until);
  }

  Future<void> _copyToday() async {
    final items = c.todayTasks;
    final buffer = StringBuffer();
    for (var i = 0; i < items.length; i++) {
      final task = items[i];
      final group = c.groups.where((item) => item.id == task.listId);
      final groupName = group.isEmpty ? '' : ' — ${group.first.name}';
      buffer.writeln('${i + 1}. ${task.text.replaceAll('\n', ' ')} — ${_formatTwelveHour(context, TimeOfDay(hour: task.hour, minute: task.minute))}$groupName — ${_statusLabel(task.status)}');
    }
    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('تم نسخ قائمة اليوم.', 'Today list copied.'))),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = await PlannerController.create();
  await NotificationService.initialize();
  await NotificationService.refresh(controller);
  runApp(InjazApp(controller: controller));
}