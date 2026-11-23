// DareMoto: the account's plan and usage, read from the account server
// (GET /api/billing/status, same data as the "Il mio account" web page), and the
// helpers the connection error dialog uses when the server refuses a connection
// because of the plan.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../desktop/pages/desktop_setting_page.dart';
import '../../models/platform_model.dart';
import '../../utils/multi_window_manager.dart';
import 'login.dart';
import '../../utils/http_service.dart' as http;

class DareMotoPlan {
  final String plan;
  final String planName;
  final int machinesUsed;
  final int machinesLimit;
  final int sessionsUsed;
  final int sessionsLimit;
  final String note;

  DareMotoPlan({
    required this.plan,
    required this.planName,
    required this.machinesUsed,
    required this.machinesLimit,
    required this.sessionsUsed,
    required this.sessionsLimit,
    required this.note,
  });

  bool get isFree => plan == 'free';

  static int _int(dynamic v) => v is int ? v : int.tryParse('$v') ?? 0;

  static String _date(int unix) {
    const months = [
      'gennaio', 'febbraio', 'marzo', 'aprile', 'maggio', 'giugno', 'luglio',
      'agosto', 'settembre', 'ottobre', 'novembre', 'dicembre'
    ];
    final d = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  factory DareMotoPlan.fromJson(Map<String, dynamic> s) {
    final sub = (s['subscription'] as Map?) ?? {};
    final limits = (s['limits'] as Map?) ?? {};
    final usage = (s['usage'] as Map?) ?? {};
    final plan = '${s['plan'] ?? 'free'}';
    final status = '${sub['status'] ?? ''}';
    final stripe = sub['stripe'] == true;
    final periodEnd = _int(sub['current_period_end']);
    final manualUntil = _int(sub['manual_until']);
    var note = '';
    if (status == 'manual' && plan != 'free') {
      note = manualUntil > 0
          ? 'Piano offerto da Ianus Project fino al ${_date(manualUntil)}.'
          : 'Piano gestito da Ianus Project.';
    } else if (status == 'past_due') {
      note = 'Pagamento non riuscito: aggiorna il metodo di pagamento.';
    } else if (stripe && sub['cancel_at_period_end'] == true && periodEnd > 0) {
      note = 'Disdetto: resta attivo fino al ${_date(periodEnd)}.';
    } else if (stripe && periodEnd > 0) {
      note = 'Si rinnova il ${_date(periodEnd)}.';
    } else if (plan == 'free') {
      note = '1 PC negli ultimi 30 giorni e 1 sessione alla volta.';
    }
    return DareMotoPlan(
      plan: plan,
      planName: '${s['plan_name'] ?? plan}',
      machinesUsed: _int(usage['machines']),
      machinesLimit: _int(limits['machines']),
      sessionsUsed: _int(usage['sessions']),
      sessionsLimit: _int(limits['sessions']),
      note: note,
    );
  }
}

/// The plan of the signed-in account; null when signed out or unreachable.
Future<DareMotoPlan?> fetchDareMotoPlan() async {
  final token = bind.mainGetLocalOption(key: 'access_token');
  if (token.isEmpty) return null;
  final api = await bind.mainGetApiServer();
  if (api.isEmpty) return null;
  final resp = await http.get(Uri.parse('$api/api/billing/status'),
      headers: {'Authorization': 'Bearer $token'});
  if (resp.statusCode != 200) {
    throw 'Errore ${resp.statusCode}';
  }
  final body = json.decode(utf8.decode(resp.bodyBytes));
  if (body is! Map || body['code'] != 0 || body['data'] is! Map) {
    throw '${body is Map ? body['message'] ?? body['error'] : 'Risposta non valida'}';
  }
  return DareMotoPlan.fromJson(Map<String, dynamic>.from(body['data']));
}

/// "Il mio account" in the browser: plans, payments, invoices.
Future<void> openDareMotoAccountPage() async {
  var api = await bind.mainGetApiServer();
  if (api.isEmpty) api = 'https://api.daremoto.net';
  await launchUrl(Uri.parse('$api/account/'),
      mode: LaunchMode.externalApplication);
}

/// Refusals of the rendezvous server that a plan upgrade solves.
bool isDareMotoPlanLimit(String text) => text.contains('daremoto.net/account');

/// Refusals that signing in (again) solves.
bool isDareMotoLoginRequired(String text) =>
    text.contains('accedi al tuo account DareMoto') ||
    text.contains('accesso al tuo account DareMoto è scaduto');

/// Settings -> Account and the login dialog. A session window on desktop asks the main
/// window, which holds the account.
void showDareMotoLogin() {
  if (isDesktop && desktopType != DesktopType.main) {
    rustDeskWinManager.call(WindowType.Main, kWindowShowAccountLogin, '');
    return;
  }
  if (isDesktop) {
    DesktopSettingPage.switch2page(SettingsTabKey.account);
  }
  if (gFFI.userModel.userName.value.isEmpty) {
    loginDialog();
  }
}

/// Plan, usage and a link to manage the plan. Shown only when signed in.
class DareMotoPlanCard extends StatefulWidget {
  const DareMotoPlanCard({Key? key}) : super(key: key);

  @override
  State<DareMotoPlanCard> createState() => _DareMotoPlanCardState();
}

class _DareMotoPlanCardState extends State<DareMotoPlanCard> {
  DareMotoPlan? _plan;
  String _error = '';
  bool _loading = false;
  Worker? _userWorker;

  @override
  void initState() {
    super.initState();
    _load();
    _userWorker = ever(gFFI.userModel.userName, (_) => _load());
  }

  @override
  void dispose() {
    _userWorker?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (gFFI.userModel.userName.value.isEmpty) {
      if (mounted) setState(() => _plan = null);
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final p = await fetchDareMotoPlan();
      if (mounted) {
        setState(() {
          _plan = p;
          _error = '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Impossibile leggere il piano: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _usage(String label, int used, int limit, BuildContext context) {
    final full = limit > 0 && used >= limit;
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).textTheme.bodySmall?.color))),
        Text('$used / $limit',
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: full ? Colors.orange.shade800 : null)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (gFFI.userModel.userName.value.isEmpty) return const SizedBox.shrink();
      final p = _plan;
      final children = <Widget>[
        Row(
          children: [
            Expanded(
              child: Text(
                p == null ? 'Piano' : 'Piano ${p.planName}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    tooltip: 'Aggiorna',
                    icon: const Icon(Icons.refresh, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: _load,
                  ),
          ],
        ),
      ];
      if (_error.isNotEmpty && p == null) {
        children.add(Text(_error,
            style: TextStyle(fontSize: 13, color: Colors.red.shade700)));
      }
      if (p != null) {
        if (p.note.isNotEmpty) {
          children.add(Text(p.note,
              style: TextStyle(
                  fontSize: 13,
                  color: Theme.of(context).textTheme.bodySmall?.color)));
        }
        children.add(const SizedBox(height: 8));
        children.add(_usage('PC collegati negli ultimi 30 giorni',
            p.machinesUsed, p.machinesLimit, context));
        children.add(const SizedBox(height: 4));
        children.add(_usage(
            'Sessioni aperte ora', p.sessionsUsed, p.sessionsLimit, context));
      }
      children.add(const SizedBox(height: 10));
      children.add(Align(
        alignment: Alignment.centerLeft,
        child: p != null && p.isFree
            ? ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Passa a un piano superiore'),
                onPressed: openDareMotoAccountPage,
              )
            : OutlinedButton.icon(
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Gestisci il piano'),
                onPressed: openDareMotoAccountPage,
              ),
      ));
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );
    });
  }
}
