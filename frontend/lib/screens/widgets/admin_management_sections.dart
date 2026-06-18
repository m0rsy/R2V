import 'package:flutter/material.dart';

import '../../api/admin_service.dart';
import '../../api/api_exception.dart';
import '../../api/freelance_service.dart';
import '../../api/r2v_api.dart';
import 'admin_console_widgets.dart';

// =========================================================================== //
// Shared helpers
// =========================================================================== //

void _toast(BuildContext context, String message, {bool error = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AdminPalette.red : AdminPalette.green,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  Color color = AdminPalette.violet,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AdminPalette.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: const TextStyle(color: AdminPalette.text)),
      content: Text(message, style: const TextStyle(color: AdminPalette.textDim)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel', style: TextStyle(color: AdminPalette.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: color),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

// Backend application statuses are the source of truth:
// pending_review | approved | rejected | needs_more_info
const Map<String, String> _applicationStatusLabels = {
  'pending_review': 'Pending Review',
  'approved': 'Approved',
  'rejected': 'Rejected',
  'needs_more_info': 'Needs More Info',
  'all': 'All',
};

String _statusColorLabel(String status) =>
    _applicationStatusLabels[status] ?? status;

Color _statusColor(String status) {
  switch (status) {
    case 'approved':
      return AdminPalette.green;
    case 'rejected':
      return AdminPalette.red;
    case 'needs_more_info':
      return AdminPalette.blue;
    case 'pending_review':
    default:
      return AdminPalette.amber;
  }
}

// =========================================================================== //
// Freelancer Applications section (admin + super_admin)
// =========================================================================== //

class AdminApplicationsSection extends StatefulWidget {
  const AdminApplicationsSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  State<AdminApplicationsSection> createState() =>
      _AdminApplicationsSectionState();
}

class _AdminApplicationsSectionState extends State<AdminApplicationsSection> {
  String _filter = 'pending_review';
  late Future<AdminApplications> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = r2vAdmin.freelancerApplications(status: _filter);
  }

  @override
  void didUpdateWidget(covariant AdminApplicationsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _reload();
  }

  void _reload() {
    setState(() => _future = r2vAdmin.freelancerApplications(status: _filter));
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _future = r2vAdmin.freelancerApplications(status: _filter);
    });
  }

  Future<void> _approve(AdminApplication app) async {
    final ok = await _confirm(
      context,
      title: 'Approve application',
      message:
          'Approve ${app.displayName}? They will become a freelancer and appear in the directory.',
      confirmLabel: 'Approve',
      color: AdminPalette.green,
    );
    if (!ok) return;
    await _runAction(() => r2vAdmin.approveApplication(app.id),
        'Application approved');
  }

  Future<void> _reject(AdminApplication app) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminPalette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Reject application',
            style: TextStyle(color: AdminPalette.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Reject ${app.displayName}? You may add an optional reason.',
                style: const TextStyle(color: AdminPalette.textDim)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(color: AdminPalette.text),
              decoration: InputDecoration(
                hintText: 'Reason (optional)',
                hintStyle: const TextStyle(color: AdminPalette.textDim),
                filled: true,
                fillColor: AdminPalette.inputGlass,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AdminPalette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AdminPalette.border),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AdminPalette.textDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AdminPalette.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final note = controller.text.trim();
    await _runAction(
      () => r2vAdmin.rejectApplication(app.id, note: note.isEmpty ? null : note),
      'Application rejected',
    );
  }

  Future<void> _requestInfo(AdminApplication app) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AdminPalette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Request more info',
            style: TextStyle(color: AdminPalette.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Ask ${app.displayName} for more information before deciding.',
                style: const TextStyle(color: AdminPalette.textDim)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(color: AdminPalette.text),
              decoration: InputDecoration(
                hintText: 'What do you need from the applicant?',
                hintStyle: const TextStyle(color: AdminPalette.textDim),
                filled: true,
                fillColor: AdminPalette.inputGlass,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AdminPalette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AdminPalette.border),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AdminPalette.textDim)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AdminPalette.blue),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send request'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final note = controller.text.trim();
    await _runAction(
      () => r2vAdmin.requestMoreInfo(app.id, note: note.isEmpty ? null : note),
      'Requested more info',
    );
  }

  Future<void> _runAction(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _toast(context, success);
      _reload();
    } catch (e) {
      if (mounted) {
        _toast(context,
            e is ApiException ? e.message : 'Action failed', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<AdminApplications>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(cards: [
              AdminMetricCard(
                label: 'Total',
                value: '${data.total}',
                icon: Icons.assignment_outlined,
                color: AdminPalette.violet,
              ),
              AdminMetricCard(
                label: 'Pending',
                value: '${data.pending}',
                icon: Icons.hourglass_top_rounded,
                color: AdminPalette.amber,
              ),
              AdminMetricCard(
                label: 'Approved',
                value: '${data.approved}',
                icon: Icons.verified_rounded,
                color: AdminPalette.green,
              ),
              AdminMetricCard(
                label: 'Rejected',
                value: '${data.rejected}',
                icon: Icons.block_rounded,
                color: AdminPalette.red,
              ),
            ]),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              children: [
                for (final f in const [
                  'pending_review',
                  'approved',
                  'rejected',
                  'needs_more_info',
                  'all',
                ])
                  _FilterChip(
                    label: _applicationStatusLabels[f] ?? f,
                    selected: _filter == f,
                    onTap: () => _setFilter(f),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (data.applications.isEmpty)
              const AdminPanel(
                child: AdminEmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'No applications',
                  message: 'Freelancer applications will appear here for review.',
                ),
              )
            else
              for (final app in data.applications)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ApplicationCard(
                    app: app,
                    busy: _busy,
                    onApprove: () => _approve(app),
                    onReject: () => _reject(app),
                    onRequestInfo: () => _requestInfo(app),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({
    required this.app,
    required this.busy,
    required this.onApprove,
    required this.onReject,
    required this.onRequestInfo,
  });

  final AdminApplication app;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onRequestInfo;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AdminPalette.violet.withOpacity(0.18),
                backgroundImage: (app.avatarUrl != null && app.avatarUrl!.isNotEmpty)
                    ? NetworkImage(app.avatarUrl!)
                    : null,
                child: (app.avatarUrl == null || app.avatarUrl!.isEmpty)
                    ? const Icon(Icons.person, color: AdminPalette.violet)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(app.displayName,
                        style: const TextStyle(
                            color: AdminPalette.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800)),
                    Text(app.title,
                        style: const TextStyle(
                            color: AdminPalette.textDim, fontSize: 13)),
                  ],
                ),
              ),
              AdminStatusPill(
                label: _statusColorLabel(app.status),
                color: _statusColor(app.status),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (app.email != null)
            Text('${app.username ?? ''}  ·  ${app.email}',
                style: const TextStyle(color: AdminPalette.textDim, fontSize: 12)),
          if (app.experience != null && app.experience!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(app.experience!,
                style: const TextStyle(
                    color: AdminPalette.text, fontSize: 13, height: 1.4)),
          ],
          if (app.message != null && app.message!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(app.message!,
                style: const TextStyle(
                    color: AdminPalette.textDim, fontSize: 12.5, height: 1.4)),
          ],
          if (app.skills.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in app.skills)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AdminPalette.blue.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AdminPalette.blue.withOpacity(0.3)),
                    ),
                    child: Text(s,
                        style: const TextStyle(
                            color: AdminPalette.blue,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 18,
            runSpacing: 6,
            children: [
              if (app.expectedPriceRange != null &&
                  app.expectedPriceRange!.isNotEmpty)
                _Meta(
                    label: 'Expected price',
                    value: app.expectedPriceRange!),
              _Meta(
                  label: 'Applied',
                  value: app.createdAt.isNotEmpty
                      ? app.createdAt.split('T').first
                      : '—'),
            ],
          ),
          if (app.portfolioLinks.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('PORTFOLIO',
                style: TextStyle(
                    color: AdminPalette.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5)),
            const SizedBox(height: 4),
            for (final link in app.portfolioLinks)
              Text(link,
                  style: const TextStyle(
                      color: AdminPalette.blue, fontSize: 12, height: 1.5)),
          ],
          if (app.adminNote != null && app.adminNote!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AdminPalette.bg1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AdminPalette.border),
              ),
              child: Text('Note: ${app.adminNote!}',
                  style: const TextStyle(
                      color: AdminPalette.textDim, fontSize: 12)),
            ),
          ],
          if (app.status == 'pending_review' ||
              app.status == 'needs_more_info') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onApprove,
                    style: FilledButton.styleFrom(
                        backgroundColor: AdminPalette.green),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AdminPalette.red,
                      side: const BorderSide(color: AdminPalette.red),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: busy ? null : onRequestInfo,
                style: TextButton.styleFrom(
                    foregroundColor: AdminPalette.blue),
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                label: const Text('Request more info'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: const TextStyle(
                color: AdminPalette.textDim,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                color: AdminPalette.text,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AdminPalette.violet.withOpacity(0.18)
          : Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? AdminPalette.violet : AdminPalette.border,
            ),
          ),
          child: Text(label,
              style: TextStyle(
                color: selected ? AdminPalette.violet : AdminPalette.textDim,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              )),
        ),
      ),
    );
  }
}

// =========================================================================== //
// Admins Management section (super_admin only)
// =========================================================================== //

class AdminManagementSection extends StatefulWidget {
  const AdminManagementSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  State<AdminManagementSection> createState() => _AdminManagementSectionState();
}

class _AdminManagementSectionState extends State<AdminManagementSection> {
  late Future<_AdminMgmtData> _future;
  bool _busy = false;
  String _userSearch = '';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant AdminManagementSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _reload();
  }

  Future<_AdminMgmtData> _load() async {
    final accounts = await r2vAdmin.admins();
    final users = await r2vAdmin.users();
    return _AdminMgmtData(accounts: accounts, users: users);
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _runAction(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _toast(context, success);
      _reload();
    } catch (e) {
      if (mounted) {
        _toast(context,
            e is ApiException ? e.message : 'Action failed', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createAdmin() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CreateAdminDialog(),
    );
    if (!mounted) return;
    if (created == true) {
      _toast(context, 'Admin created');
      _reload();
    }
  }

  Future<void> _promote(AdminUser user) async {
    final ok = await _confirm(
      context,
      title: 'Promote to admin',
      message:
          'Grant admin access to ${user.username ?? user.email}? They will gain access to the admin console.',
      confirmLabel: 'Promote',
    );
    if (!ok) return;
    await _runAction(() => r2vAdmin.promoteToAdmin(user.id), 'User promoted to admin');
  }

  Future<void> _demote(AdminAccount account) async {
    final ok = await _confirm(
      context,
      title: 'Demote admin',
      message:
          'Remove admin access from ${account.username ?? account.email}? They will return to a normal user.',
      confirmLabel: 'Demote',
      color: AdminPalette.red,
    );
    if (!ok) return;
    await _runAction(() => r2vAdmin.demoteAdmin(account.id), 'Admin demoted');
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<_AdminMgmtData>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        final accounts = data.accounts;
        final promotable = data.users.users
            .where((u) => u.role == 'user' || u.role == 'freelancer')
            .where((u) {
          if (_userSearch.isEmpty) return true;
          final q = _userSearch.toLowerCase();
          return (u.username ?? '').toLowerCase().contains(q) ||
              u.email.toLowerCase().contains(q);
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(cards: [
              AdminMetricCard(
                label: 'Admins',
                value: '${accounts.admins}',
                icon: Icons.shield_rounded,
                color: AdminPalette.violet,
              ),
              AdminMetricCard(
                label: 'Super Admins',
                value: '${accounts.superAdmins}',
                icon: Icons.workspace_premium_rounded,
                color: AdminPalette.amber,
              ),
              AdminMetricCard(
                label: 'Total Staff',
                value: '${accounts.total}',
                icon: Icons.groups_rounded,
                color: AdminPalette.blue,
              ),
            ]),
            const SizedBox(height: 18),
            AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: AdminPanelHeader(
                          icon: Icons.admin_panel_settings_rounded,
                          title: 'Admin accounts',
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _busy ? null : _createAdmin,
                        style: FilledButton.styleFrom(
                            backgroundColor: AdminPalette.violet),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Create Admin'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  for (final account in accounts.accounts)
                    _AdminRow(
                      account: account,
                      busy: _busy,
                      onDemote: account.isSuperAdmin ? null : () => _demote(account),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AdminPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AdminPanelHeader(
                    icon: Icons.person_add_alt_1_rounded,
                    title: 'Promote a user',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: (v) => setState(() => _userSearch = v),
                    style: const TextStyle(color: AdminPalette.text),
                    decoration: InputDecoration(
                      hintText: 'Search users by name or email',
                      hintStyle: const TextStyle(color: AdminPalette.textDim),
                      prefixIcon:
                          const Icon(Icons.search, color: AdminPalette.textDim),
                      filled: true,
                      fillColor: AdminPalette.inputGlass,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AdminPalette.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AdminPalette.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (promotable.isEmpty)
                    const AdminEmptyState(
                      icon: Icons.person_search_rounded,
                      title: 'No matching users',
                      message: 'Try a different search term.',
                      compact: true,
                    )
                  else
                    for (final u in promotable.take(20))
                      _PromotableRow(
                        user: u,
                        busy: _busy,
                        onPromote: () => _promote(u),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AdminMgmtData {
  const _AdminMgmtData({required this.accounts, required this.users});
  final AdminAccounts accounts;
  final AdminUsers users;
}

class _AdminRow extends StatelessWidget {
  const _AdminRow({required this.account, required this.busy, this.onDemote});

  final AdminAccount account;
  final bool busy;
  final VoidCallback? onDemote;

  @override
  Widget build(BuildContext context) {
    final isSuper = account.isSuperAdmin;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: (isSuper ? AdminPalette.amber : AdminPalette.violet)
                .withOpacity(0.16),
            child: Icon(
              isSuper ? Icons.workspace_premium_rounded : Icons.shield_rounded,
              size: 18,
              color: isSuper ? AdminPalette.amber : AdminPalette.violet,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.username ?? account.email,
                    style: const TextStyle(
                        color: AdminPalette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(account.email,
                    style: const TextStyle(
                        color: AdminPalette.textDim, fontSize: 12)),
              ],
            ),
          ),
          AdminStatusPill(
            label: isSuper ? 'Super Admin' : 'Admin',
            color: isSuper ? AdminPalette.amber : AdminPalette.violet,
          ),
          if (onDemote != null) ...[
            const SizedBox(width: 10),
            IconButton(
              tooltip: 'Demote to user',
              onPressed: busy ? null : onDemote,
              icon: const Icon(Icons.remove_moderator_rounded,
                  color: AdminPalette.red, size: 20),
            ),
          ],
        ],
      ),
    );
  }
}

class _PromotableRow extends StatelessWidget {
  const _PromotableRow({
    required this.user,
    required this.busy,
    required this.onPromote,
  });

  final AdminUser user;
  final bool busy;
  final VoidCallback onPromote;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AdminPalette.blue.withOpacity(0.14),
            child: const Icon(Icons.person, size: 18, color: AdminPalette.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.username ?? user.email,
                    style: const TextStyle(
                        color: AdminPalette.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text('${user.email}  ·  ${user.role}',
                    style: const TextStyle(
                        color: AdminPalette.textDim, fontSize: 12)),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: busy ? null : onPromote,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminPalette.violet,
              side: const BorderSide(color: AdminPalette.violet),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.upgrade_rounded, size: 18),
            label: const Text('Promote'),
          ),
        ],
      ),
    );
  }
}

class _CreateAdminDialog extends StatefulWidget {
  const _CreateAdminDialog();

  @override
  State<_CreateAdminDialog> createState() => _CreateAdminDialogState();
}

class _CreateAdminDialogState extends State<_CreateAdminDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await r2vAdmin.createAdmin(
        email: _email.text.trim(),
        username: _name.text.trim(),
        password: _password.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = e is ApiException ? e.message : 'Could not create admin';
        _busy = false;
      });
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AdminPalette.textDim),
        filled: true,
        fillColor: AdminPalette.inputGlass,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminPalette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdminPalette.border),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AdminPalette.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('Create admin',
          style: TextStyle(color: AdminPalette.text)),
      content: SizedBox(
        width: 380,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                style: const TextStyle(color: AdminPalette.text),
                decoration: _dec('Username / name'),
                validator: (v) =>
                    (v == null || v.trim().length < 3) ? 'Min 3 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                style: const TextStyle(color: AdminPalette.text),
                decoration: _dec('Email'),
                validator: (v) => (v == null || !v.contains('@'))
                    ? 'Enter a valid email'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                style: const TextStyle(color: AdminPalette.text),
                decoration: _dec('Password'),
                validator: (v) =>
                    (v == null || v.length < 8) ? 'Min 8 characters' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirm,
                obscureText: true,
                style: const TextStyle(color: AdminPalette.text),
                decoration: _dec('Confirm password'),
                validator: (v) =>
                    v != _password.text ? 'Passwords do not match' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: const TextStyle(
                        color: AdminPalette.red, fontSize: 12.5)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel',
              style: TextStyle(color: AdminPalette.textDim)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AdminPalette.violet),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Create'),
        ),
      ],
    );
  }
}

// =========================================================================== //
// Users management (search, ban/unban, role — real privileges)
// =========================================================================== //

Color _roleColor(String role) {
  switch (role) {
    case 'super_admin':
      return AdminPalette.amber;
    case 'admin':
      return AdminPalette.violet;
    case 'freelancer':
      return AdminPalette.blue;
    default:
      return AdminPalette.green;
  }
}

String _shortId(String id) => id.length > 8 ? '${id.substring(0, 8)}…' : id;

const List<String> _assignableRoles = [
  'user',
  'freelancer',
  'admin',
  'super_admin',
];

class AdminUsersManageSection extends StatefulWidget {
  const AdminUsersManageSection({
    super.key,
    required this.refreshTick,
    required this.isSuperAdmin,
  });

  final int refreshTick;
  final bool isSuperAdmin;

  @override
  State<AdminUsersManageSection> createState() =>
      _AdminUsersManageSectionState();
}

class _UsersMgmtData {
  const _UsersMgmtData({required this.users, required this.myId});
  final AdminUsers users;
  final String myId;
}

class _AdminUsersManageSectionState extends State<AdminUsersManageSection> {
  static const _statusFilters = ['all', 'active', 'banned'];
  static const _roleFilters = ['all', 'user', 'freelancer', 'admin', 'super_admin'];

  String _status = 'all';
  String _role = 'all';
  String _search = '';
  bool _busy = false;
  final _searchController = TextEditingController();
  late Future<_UsersMgmtData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdminUsersManageSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _reload();
  }

  Future<_UsersMgmtData> _load() async {
    final users = await r2vAdmin.users(
      q: _search,
      role: _role,
      status: _status,
    );
    String myId = '';
    try {
      final me = await r2vAuth.me();
      myId = (me['id'] ?? '').toString();
    } catch (_) {
      // Self-protection is also enforced server-side; this only hides the button.
    }
    return _UsersMgmtData(users: users, myId: myId);
  }

  void _reload() => setState(() => _future = _load());

  void _setStatus(String value) {
    if (_status == value) return;
    setState(() {
      _status = value;
      _future = _load();
    });
  }

  void _setRole(String value) {
    if (_role == value) return;
    setState(() {
      _role = value;
      _future = _load();
    });
  }

  Future<void> _runAction(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _toast(context, success);
      _reload();
    } catch (e) {
      if (mounted) {
        _toast(context, e is ApiException ? e.message : 'Action failed',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _ban(AdminUser user) async {
    final ok = await _confirm(
      context,
      title: 'Ban user',
      message:
          'Ban ${user.username ?? user.email}? They will be signed out and unable to log in until unbanned.',
      confirmLabel: 'Ban',
      color: AdminPalette.red,
    );
    if (!ok) return;
    await _runAction(() => r2vAdmin.banUser(user.id), 'User banned');
  }

  Future<void> _unban(AdminUser user) async {
    final ok = await _confirm(
      context,
      title: 'Unban user',
      message: 'Restore access for ${user.username ?? user.email}?',
      confirmLabel: 'Unban',
      color: AdminPalette.green,
    );
    if (!ok) return;
    await _runAction(() => r2vAdmin.unbanUser(user.id), 'User unbanned');
  }

  Future<void> _changeRole(AdminUser user) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AdminPalette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Change role · ${user.username ?? user.email}',
            style: const TextStyle(color: AdminPalette.text, fontSize: 16)),
        children: [
          for (final r in _assignableRoles)
            RadioListTile<String>(
              value: r,
              groupValue: user.role,
              activeColor: AdminPalette.violet,
              title: Text(r,
                  style: const TextStyle(color: AdminPalette.text)),
              onChanged: (v) => Navigator.of(ctx).pop(v),
            ),
        ],
      ),
    );
    if (selected == null || selected == user.role) return;
    await _runAction(
      () => r2vAdmin.updateUserRole(user.id, selected),
      'Role updated to $selected',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<_UsersMgmtData>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        final users = data.users;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(cards: [
              AdminMetricCard(
                label: 'Total Users',
                value: '${users.total}',
                icon: Icons.group_rounded,
                color: AdminPalette.violet,
              ),
              AdminMetricCard(
                label: 'Active',
                value: '${users.active}',
                icon: Icons.verified_user_rounded,
                color: AdminPalette.green,
              ),
              AdminMetricCard(
                label: 'Freelancers',
                value: '${users.freelancers}',
                icon: Icons.work_outline_rounded,
                color: AdminPalette.blue,
              ),
              AdminMetricCard(
                label: 'Banned',
                value: '${users.suspended}',
                icon: Icons.block_rounded,
                color: AdminPalette.red,
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              style: const TextStyle(color: AdminPalette.text),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                setState(() {
                  _search = v;
                  _future = _load();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search by name or email (press enter)',
                hintStyle: const TextStyle(color: AdminPalette.textDim),
                prefixIcon:
                    const Icon(Icons.search, color: AdminPalette.textDim),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close,
                            color: AdminPalette.textDim, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _search = '';
                            _future = _load();
                          });
                        },
                      ),
                filled: true,
                fillColor: AdminPalette.inputGlass,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AdminPalette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AdminPalette.border),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final f in _statusFilters)
                _FilterChip(
                  label: f[0].toUpperCase() + f.substring(1),
                  selected: _status == f,
                  onTap: () => _setStatus(f),
                ),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final f in _roleFilters)
                _FilterChip(
                  label: f == 'all'
                      ? 'All roles'
                      : f.replaceAll('_', ' '),
                  selected: _role == f,
                  onTap: () => _setRole(f),
                ),
            ]),
            const SizedBox(height: 16),
            if (users.users.isEmpty)
              const AdminPanel(
                child: AdminEmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'No users found',
                  message: 'Try a different search term or filter.',
                ),
              )
            else
              for (final u in users.users)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _UserManageCard(
                    user: u,
                    busy: _busy,
                    isSelf: u.id == data.myId,
                    canManageRoles: widget.isSuperAdmin,
                    onBan: () => _ban(u),
                    onUnban: () => _unban(u),
                    onChangeRole: () => _changeRole(u),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _UserManageCard extends StatelessWidget {
  const _UserManageCard({
    required this.user,
    required this.busy,
    required this.isSelf,
    required this.canManageRoles,
    required this.onBan,
    required this.onUnban,
    required this.onChangeRole,
  });

  final AdminUser user;
  final bool busy;
  final bool isSelf;
  final bool canManageRoles;
  final VoidCallback onBan;
  final VoidCallback onUnban;
  final VoidCallback onChangeRole;

  @override
  Widget build(BuildContext context) {
    final isStaff = user.role == 'admin' || user.role == 'super_admin';
    // Admins/super_admins can't be banned (demote first); never ban yourself.
    final canBan = user.isActive && !isStaff && !isSelf;
    return AdminPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor:
                (user.isActive ? AdminPalette.blue : AdminPalette.red)
                    .withOpacity(0.16),
            child: Icon(
              user.isActive ? Icons.person_rounded : Icons.person_off_rounded,
              size: 20,
              color: user.isActive ? AdminPalette.blue : AdminPalette.red,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        user.username?.isNotEmpty == true
                            ? user.username!
                            : user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AdminPalette.text,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (isSelf) ...[
                      const SizedBox(width: 8),
                      const AdminStatusPill(label: 'you', color: AdminPalette.amber),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text('${user.email}  ·  ${_shortId(user.id)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AdminPalette.textDim, fontSize: 12)),
                ]),
          ),
          const SizedBox(width: 10),
          AdminStatusPill(label: user.role, color: _roleColor(user.role)),
          const SizedBox(width: 8),
          AdminStatusPill(
            label: user.isActive ? 'active' : 'banned',
            color: user.isActive ? AdminPalette.green : AdminPalette.red,
          ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 10, children: [
          if (canBan)
            OutlinedButton.icon(
              onPressed: busy ? null : onBan,
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminPalette.red,
                side: const BorderSide(color: AdminPalette.red),
              ),
              icon: const Icon(Icons.block_rounded, size: 18),
              label: const Text('Ban'),
            ),
          if (!user.isActive)
            FilledButton.icon(
              onPressed: busy ? null : onUnban,
              style: FilledButton.styleFrom(backgroundColor: AdminPalette.green),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('Unban'),
            ),
          if (canManageRoles)
            OutlinedButton.icon(
              onPressed: busy ? null : onChangeRole,
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminPalette.violet,
                side: const BorderSide(color: AdminPalette.violet),
              ),
              icon: const Icon(Icons.shield_rounded, size: 18),
              label: const Text('Change role'),
            ),
          if (!canBan && user.isActive && isStaff)
            const Text('Staff account — demote before banning',
                style: TextStyle(color: AdminPalette.textDim, fontSize: 12)),
        ]),
      ]),
    );
  }
}

// =========================================================================== //
// Asset moderation (hide / restore / hard delete — real privileges)
// =========================================================================== //

Color _assetVisibilityColor(String visibility) {
  switch (visibility) {
    case 'published':
      return AdminPalette.green;
    case 'draft':
      return AdminPalette.amber;
    case 'removed':
      return AdminPalette.red;
    default:
      return AdminPalette.textDim;
  }
}

class AdminAssetsManageSection extends StatefulWidget {
  const AdminAssetsManageSection({super.key, required this.refreshTick});

  final int refreshTick;

  @override
  State<AdminAssetsManageSection> createState() =>
      _AdminAssetsManageSectionState();
}

class _AdminAssetsManageSectionState extends State<AdminAssetsManageSection> {
  static const _filters = ['all', 'published', 'draft', 'removed'];
  String _filter = 'all';
  String _search = '';
  bool _busy = false;
  final _searchController = TextEditingController();
  late Future<AdminAssets> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AdminAssetsManageSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _reload();
  }

  Future<AdminAssets> _load() =>
      r2vAdmin.listAssets(q: _search, visibility: _filter);

  void _reload() => setState(() => _future = _load());

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _future = _load();
    });
  }

  Future<void> _runAction(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) _toast(context, success);
      _reload();
    } catch (e) {
      if (mounted) {
        _toast(context, e is ApiException ? e.message : 'Action failed',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hide(AdminAsset a) async {
    final ok = await _confirm(
      context,
      title: 'Hide asset',
      message:
          'Hide "${a.title.isEmpty ? 'Untitled' : a.title}"? It will be removed from the public marketplace but can be restored.',
      confirmLabel: 'Hide',
      color: AdminPalette.amber,
    );
    if (!ok) return;
    await _runAction(() => r2vAdmin.hideAsset(a.id), 'Asset hidden');
  }

  Future<void> _restore(AdminAsset a) async {
    await _runAction(() => r2vAdmin.restoreAsset(a.id), 'Asset restored');
  }

  Future<void> _delete(AdminAsset a) async {
    final ok = await _confirm(
      context,
      title: 'Permanently delete asset',
      message:
          'Permanently delete "${a.title.isEmpty ? 'Untitled' : a.title}"? This cannot be undone. Consider hiding it instead.',
      confirmLabel: 'Delete forever',
      color: AdminPalette.red,
    );
    if (!ok) return;
    await _runAction(() => r2vAdmin.deleteAsset(a.id), 'Asset deleted');
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<AdminAssets>(
      future: _future,
      onRetry: _reload,
      builder: (context, data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(cards: [
              AdminMetricCard(
                label: 'Total Assets',
                value: '${data.total}',
                icon: Icons.view_in_ar_rounded,
                color: AdminPalette.violet,
              ),
              AdminMetricCard(
                label: 'Published',
                value: '${data.published}',
                icon: Icons.verified_rounded,
                color: AdminPalette.green,
              ),
              AdminMetricCard(
                label: 'Draft',
                value: '${data.draft}',
                icon: Icons.edit_note_rounded,
                color: AdminPalette.amber,
              ),
              AdminMetricCard(
                label: 'Removed',
                value: '${data.removed}',
                icon: Icons.visibility_off_rounded,
                color: AdminPalette.red,
              ),
            ]),
            const SizedBox(height: 16),
            TextField(
              controller: _searchController,
              style: const TextStyle(color: AdminPalette.text),
              textInputAction: TextInputAction.search,
              onSubmitted: (v) {
                setState(() {
                  _search = v;
                  _future = _load();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search assets by title (press enter)',
                hintStyle: const TextStyle(color: AdminPalette.textDim),
                prefixIcon:
                    const Icon(Icons.search, color: AdminPalette.textDim),
                suffixIcon: _search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close,
                            color: AdminPalette.textDim, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _search = '';
                            _future = _load();
                          });
                        },
                      ),
                filled: true,
                fillColor: AdminPalette.inputGlass,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AdminPalette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AdminPalette.border),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final f in _filters)
                _FilterChip(
                  label: f[0].toUpperCase() + f.substring(1),
                  selected: _filter == f,
                  onTap: () => _setFilter(f),
                ),
            ]),
            const SizedBox(height: 16),
            if (data.assets.isEmpty)
              const AdminPanel(
                child: AdminEmptyState(
                  icon: Icons.view_in_ar_outlined,
                  title: 'No assets',
                  message: 'Marketplace assets will appear here for moderation.',
                ),
              )
            else
              for (final a in data.assets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _AssetManageCard(
                    a: a,
                    busy: _busy,
                    onHide: () => _hide(a),
                    onRestore: () => _restore(a),
                    onDelete: () => _delete(a),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _AssetManageCard extends StatelessWidget {
  const _AssetManageCard({
    required this.a,
    required this.busy,
    required this.onHide,
    required this.onRestore,
    required this.onDelete,
  });

  final AdminAsset a;
  final bool busy;
  final VoidCallback onHide;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final removed = a.isRemoved;
    final creator = (a.creatorUsername != null && a.creatorUsername!.isNotEmpty)
        ? a.creatorUsername!
        : 'Creator ${_shortId(a.creatorId)}';
    return AdminPanel(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AdminPalette.violet.withOpacity(0.16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminPalette.violet.withOpacity(0.3)),
            ),
            child: const Icon(Icons.category_rounded,
                color: AdminPalette.violet, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.title.isEmpty ? 'Untitled' : a.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AdminPalette.text,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(creator,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AdminPalette.textDim, fontSize: 12)),
                ]),
          ),
          const SizedBox(width: 10),
          AdminStatusPill(
            label: a.visibility,
            color: _assetVisibilityColor(a.visibility),
          ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 6, children: [
          _Meta(label: 'Category', value: a.category.isEmpty ? '—' : a.category),
          _Meta(label: 'Style', value: a.style.isEmpty ? '—' : a.style),
          _Meta(
            label: 'Price',
            value: a.isPaid ? '${a.currency.toUpperCase()} ${a.price}' : 'Free',
          ),
          _Meta(label: 'Created', value: _shortDate(a.createdAt)),
        ]),
        if (removed && a.moderationReason != null &&
            a.moderationReason!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminPalette.red.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminPalette.red.withOpacity(0.3)),
            ),
            child: Text('Removed: ${a.moderationReason!}',
                style: const TextStyle(
                    color: AdminPalette.textDim, fontSize: 12)),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(spacing: 12, runSpacing: 10, children: [
          if (removed)
            FilledButton.icon(
              onPressed: busy ? null : onRestore,
              style: FilledButton.styleFrom(backgroundColor: AdminPalette.green),
              icon: const Icon(Icons.restore_rounded, size: 18),
              label: const Text('Restore'),
            )
          else
            OutlinedButton.icon(
              onPressed: busy ? null : onHide,
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminPalette.amber,
                side: const BorderSide(color: AdminPalette.amber),
              ),
              icon: const Icon(Icons.visibility_off_rounded, size: 18),
              label: const Text('Hide'),
            ),
          OutlinedButton.icon(
            onPressed: busy ? null : onDelete,
            style: OutlinedButton.styleFrom(
              foregroundColor: AdminPalette.red,
              side: const BorderSide(color: AdminPalette.red),
            ),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('Delete'),
          ),
        ]),
      ]),
    );
  }
}

// =========================================================================== //
// Shared freelance-admin helpers
// =========================================================================== //

Color _freelanceStatusColor(String status) {
  switch (status) {
    case 'approved':
    case 'active':
    case 'completed':
    case 'accepted':
      return AdminPalette.green;
    case 'pending':
    case 'pending_review':
    case 'draft':
    case 'in_progress':
    case 'delivered':
      return AdminPalette.amber;
    case 'revision_requested':
      return AdminPalette.blue;
    case 'suspended':
    case 'rejected':
    case 'disputed':
      return AdminPalette.red;
    default:
      return AdminPalette.textDim;
  }
}

String _shortDate(String raw) =>
    raw.isNotEmpty && raw.contains('T') ? raw.split('T').first : (raw.isEmpty ? '—' : raw);

// =========================================================================== //
// Freelancers management (view + suspend/reactivate)
// =========================================================================== //

class AdminFreelancersManageSection extends StatefulWidget {
  const AdminFreelancersManageSection({super.key, required this.refreshTick});
  final int refreshTick;
  @override
  State<AdminFreelancersManageSection> createState() =>
      _AdminFreelancersManageSectionState();
}

class _AdminFreelancersManageSectionState
    extends State<AdminFreelancersManageSection> {
  static const _filters = ['all', 'approved', 'pending', 'suspended', 'rejected'];
  String _filter = 'all';
  bool _busy = false;
  late Future<List<FreelanceProfile>> _future;

  @override
  void initState() {
    super.initState();
    _future = r2vAdmin.freelanceProfiles(status: _filter);
  }

  @override
  void didUpdateWidget(covariant AdminFreelancersManageSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _reload();
  }

  void _reload() =>
      setState(() => _future = r2vAdmin.freelanceProfiles(status: _filter));

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _future = r2vAdmin.freelanceProfiles(status: _filter);
    });
  }

  Future<void> _setStatus(FreelanceProfile f, String status, String label) async {
    final ok = await _confirm(
      context,
      title: '$label freelancer',
      message: '$label ${f.displayName.isEmpty ? f.username : f.displayName}?',
      confirmLabel: label,
      color: status == 'approved' ? AdminPalette.green : AdminPalette.red,
    );
    if (!ok) return;
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await r2vAdmin.setFreelancerStatus(f.id, status);
      if (mounted) _toast(context, '$label successful');
      _reload();
    } catch (e) {
      if (mounted) {
        _toast(context, e is ApiException ? e.message : 'Action failed',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<List<FreelanceProfile>>(
      future: _future,
      onRetry: _reload,
      builder: (context, rows) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(cards: [
              AdminMetricCard(
                label: 'Showing',
                value: '${rows.length}',
                icon: Icons.work_outline_rounded,
                color: AdminPalette.violet,
              ),
              AdminMetricCard(
                label: 'Approved',
                value: '${rows.where((f) => f.status == 'approved').length}',
                icon: Icons.verified_user_rounded,
                color: AdminPalette.green,
              ),
              AdminMetricCard(
                label: 'Suspended',
                value: '${rows.where((f) => f.status == 'suspended').length}',
                icon: Icons.block_rounded,
                color: AdminPalette.red,
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 10, children: [
              for (final f in _filters)
                _FilterChip(
                  label: f[0].toUpperCase() + f.substring(1),
                  selected: _filter == f,
                  onTap: () => _setFilter(f),
                ),
            ]),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const AdminPanel(
                child: AdminEmptyState(
                  icon: Icons.badge_outlined,
                  title: 'No freelancers',
                  message: 'Approved freelancer profiles will appear here.',
                ),
              )
            else
              for (final f in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _FreelancerManageCard(
                    f: f,
                    busy: _busy,
                    onSuspend: () => _setStatus(f, 'suspended', 'Suspend'),
                    onReactivate: () => _setStatus(f, 'approved', 'Reactivate'),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _FreelancerManageCard extends StatelessWidget {
  const _FreelancerManageCard({
    required this.f,
    required this.busy,
    required this.onSuspend,
    required this.onReactivate,
  });
  final FreelanceProfile f;
  final bool busy;
  final VoidCallback onSuspend;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final suspended = f.status == 'suspended';
    return AdminPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AdminPalette.violet.withValues(alpha: 0.18),
            backgroundImage: (f.avatarUrl != null && f.avatarUrl!.isNotEmpty)
                ? NetworkImage(f.avatarUrl!)
                : null,
            child: (f.avatarUrl == null || f.avatarUrl!.isEmpty)
                ? const Icon(Icons.person, color: AdminPalette.violet)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(f.displayName.isEmpty ? f.username : f.displayName,
                  style: const TextStyle(
                      color: AdminPalette.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
              Text('${f.title}  ·  ${f.email}',
                  style: const TextStyle(
                      color: AdminPalette.textDim, fontSize: 12)),
            ]),
          ),
          AdminStatusPill(
            label: f.status.isEmpty ? 'unknown' : f.status,
            color: _freelanceStatusColor(f.status),
          ),
        ]),
        if (f.bio != null && f.bio!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(f.bio!,
              style: const TextStyle(
                  color: AdminPalette.text, fontSize: 13, height: 1.4)),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 6, children: [
          _Meta(label: 'Rating', value: f.rating.toStringAsFixed(1)),
          _Meta(label: 'Completed', value: '${f.completedJobs}'),
          _Meta(label: 'Skills', value: '${f.skills.length}'),
          _Meta(label: 'Portfolio', value: '${f.portfolioLinks.length}'),
          _Meta(label: 'Joined', value: _shortDate(f.createdAt)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          if (suspended)
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onReactivate,
                style:
                    FilledButton.styleFrom(backgroundColor: AdminPalette.green),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Reactivate'),
              ),
            )
          else
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onSuspend,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminPalette.red,
                  side: const BorderSide(color: AdminPalette.red),
                ),
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Suspend'),
              ),
            ),
        ]),
      ]),
    );
  }
}

// =========================================================================== //
// Freelance services moderation (view + hide/reactivate/reject)
// =========================================================================== //

class AdminFreelanceServicesSection extends StatefulWidget {
  const AdminFreelanceServicesSection({super.key, required this.refreshTick});
  final int refreshTick;
  @override
  State<AdminFreelanceServicesSection> createState() =>
      _AdminFreelanceServicesSectionState();
}

class _AdminFreelanceServicesSectionState
    extends State<AdminFreelanceServicesSection> {
  static const _filters = ['all', 'active', 'paused', 'draft', 'rejected'];
  String _filter = 'all';
  bool _busy = false;
  late Future<List<FlService>> _future;

  @override
  void initState() {
    super.initState();
    _future = r2vAdmin.freelanceServices(status: _filter);
  }

  @override
  void didUpdateWidget(covariant AdminFreelanceServicesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _reload();
  }

  void _reload() =>
      setState(() => _future = r2vAdmin.freelanceServices(status: _filter));

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _future = r2vAdmin.freelanceServices(status: _filter);
    });
  }

  Future<void> _setStatus(FlService s, String status, String label) async {
    final ok = await _confirm(
      context,
      title: '$label service',
      message: '$label "${s.title}"?',
      confirmLabel: label,
      color: status == 'active' ? AdminPalette.green : AdminPalette.red,
    );
    if (!ok || _busy) return;
    setState(() => _busy = true);
    try {
      await r2vAdmin.setServiceStatus(s.id, status);
      if (mounted) _toast(context, '$label successful');
      _reload();
    } catch (e) {
      if (mounted) {
        _toast(context, e is ApiException ? e.message : 'Action failed',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminAsyncView<List<FlService>>(
      future: _future,
      onRetry: _reload,
      builder: (context, rows) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminMetricGrid(cards: [
              AdminMetricCard(
                label: 'Showing',
                value: '${rows.length}',
                icon: Icons.design_services_rounded,
                color: AdminPalette.violet,
              ),
              AdminMetricCard(
                label: 'Active',
                value: '${rows.where((s) => s.status == 'active').length}',
                icon: Icons.check_circle_rounded,
                color: AdminPalette.green,
              ),
              AdminMetricCard(
                label: 'Hidden',
                value:
                    '${rows.where((s) => s.status != 'active').length}',
                icon: Icons.visibility_off_rounded,
                color: AdminPalette.amber,
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(spacing: 10, children: [
              for (final f in _filters)
                _FilterChip(
                  label: f[0].toUpperCase() + f.substring(1),
                  selected: _filter == f,
                  onTap: () => _setFilter(f),
                ),
            ]),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              const AdminPanel(
                child: AdminEmptyState(
                  icon: Icons.design_services_outlined,
                  title: 'No services',
                  message: 'Freelance services will appear here for moderation.',
                ),
              )
            else
              for (final s in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _ServiceModerationCard(
                    s: s,
                    busy: _busy,
                    onHide: () => _setStatus(s, 'paused', 'Hide'),
                    onReject: () => _setStatus(s, 'rejected', 'Reject'),
                    onReactivate: () => _setStatus(s, 'active', 'Reactivate'),
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _ServiceModerationCard extends StatelessWidget {
  const _ServiceModerationCard({
    required this.s,
    required this.busy,
    required this.onHide,
    required this.onReject,
    required this.onReactivate,
  });
  final FlService s;
  final bool busy;
  final VoidCallback onHide;
  final VoidCallback onReject;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final active = s.status == 'active';
    return AdminPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(s.title,
                style: const TextStyle(
                    color: AdminPalette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ),
          AdminStatusPill(
            label: s.status,
            color: _freelanceStatusColor(s.status),
          ),
        ]),
        const SizedBox(height: 4),
        Text(s.freelancer?.displayName ?? 'Freelancer',
            style: const TextStyle(color: AdminPalette.textDim, fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 6, children: [
          _Meta(label: 'Category', value: s.category),
          _Meta(label: 'Price', value: '\$${s.startingPrice.toStringAsFixed(0)}'),
          _Meta(label: 'Delivery', value: '${s.deliveryDays}d'),
          _Meta(label: 'Created', value: _shortDate(s.createdAt)),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          if (active) ...[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onHide,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminPalette.amber,
                  side: const BorderSide(color: AdminPalette.amber),
                ),
                icon: const Icon(Icons.visibility_off_rounded, size: 18),
                label: const Text('Hide'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : onReject,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminPalette.red,
                  side: const BorderSide(color: AdminPalette.red),
                ),
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('Reject'),
              ),
            ),
          ] else
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onReactivate,
                style:
                    FilledButton.styleFrom(backgroundColor: AdminPalette.green),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Reactivate'),
              ),
            ),
        ]),
      ]),
    );
  }
}

// =========================================================================== //
// Freelance orders / disputes (real metrics + read-only management)
// =========================================================================== //

class AdminFreelanceOrdersSection extends StatefulWidget {
  const AdminFreelanceOrdersSection({super.key, required this.refreshTick});
  final int refreshTick;
  @override
  State<AdminFreelanceOrdersSection> createState() =>
      _AdminFreelanceOrdersSectionState();
}

class _AdminFreelanceOrdersSectionState
    extends State<AdminFreelanceOrdersSection> {
  static const _filters = [
    'all',
    'pending',
    'accepted',
    'in_progress',
    'delivered',
    'revision_requested',
    'completed',
    'disputed',
    'cancelled',
  ];
  String _filter = 'all';
  late Future<List<FlOrder>> _ordersFuture;
  late Future<AdminFreelanceSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _ordersFuture = r2vAdmin.freelanceOrders(status: _filter);
    _summaryFuture = r2vAdmin.freelanceSummary();
  }

  @override
  void didUpdateWidget(covariant AdminFreelanceOrdersSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _reloadAll();
  }

  void _reloadAll() {
    setState(() {
      _ordersFuture = r2vAdmin.freelanceOrders(status: _filter);
      _summaryFuture = r2vAdmin.freelanceSummary();
    });
  }

  void _setFilter(String value) {
    if (_filter == value) return;
    setState(() {
      _filter = value;
      _ordersFuture = r2vAdmin.freelanceOrders(status: _filter);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Real metrics from GET /admin/freelance/summary.
        FutureBuilder<AdminFreelanceSummary>(
          future: _summaryFuture,
          builder: (context, snap) {
            final s = snap.data;
            return AdminMetricGrid(cards: [
              AdminMetricCard(
                label: 'Applications',
                value: '${s?.applications ?? 0}',
                icon: Icons.assignment_ind_rounded,
                color: AdminPalette.violet,
              ),
              AdminMetricCard(
                label: 'Freelancers',
                value: '${s?.freelancers ?? 0}',
                icon: Icons.work_outline_rounded,
                color: AdminPalette.blue,
              ),
              AdminMetricCard(
                label: 'Services',
                value: '${s?.services ?? 0}',
                icon: Icons.design_services_rounded,
                color: AdminPalette.amber,
              ),
              AdminMetricCard(
                label: 'Orders',
                value: '${s?.orders ?? 0}',
                icon: Icons.receipt_long_rounded,
                color: AdminPalette.green,
              ),
              AdminMetricCard(
                label: 'Disputed',
                value: '${s?.disputes ?? 0}',
                icon: Icons.gavel_rounded,
                color: AdminPalette.red,
              ),
              AdminMetricCard(
                label: 'Completed',
                value: '${s?.statusCount('completed') ?? 0}',
                icon: Icons.check_circle_rounded,
                color: AdminPalette.green,
              ),
            ]);
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final f in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _FilterChip(
                    label: _orderFilterLabel(f),
                    selected: _filter == f,
                    onTap: () => _setFilter(f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdminAsyncView<List<FlOrder>>(
          future: _ordersFuture,
          onRetry: _reloadAll,
          builder: (context, rows) {
            if (rows.isEmpty) {
              return const AdminPanel(
                child: AdminEmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No orders',
                  message: 'Freelance orders will appear here.',
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final o in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _OrderAdminCard(o: o),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  String _orderFilterLabel(String f) {
    if (f == 'all') return 'All';
    return f
        .split('_')
        .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }
}

class _OrderAdminCard extends StatelessWidget {
  const _OrderAdminCard({required this.o});
  final FlOrder o;

  @override
  Widget build(BuildContext context) {
    return AdminPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(o.title,
                style: const TextStyle(
                    color: AdminPalette.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ),
          AdminStatusPill(
            label: o.status,
            color: _freelanceStatusColor(o.status),
          ),
        ]),
        if (o.service != null) ...[
          const SizedBox(height: 4),
          Text('Service: ${o.service!.title}',
              style: const TextStyle(color: AdminPalette.textDim, fontSize: 12)),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 6, children: [
          _Meta(label: 'Client', value: o.client?.name ?? '—'),
          _Meta(
              label: 'Freelancer',
              value: o.freelancer?.displayName ?? '—'),
          _Meta(label: 'Budget', value: '\$${o.budget.toStringAsFixed(0)}'),
          if (o.deadline != null && o.deadline!.isNotEmpty)
            _Meta(label: 'Deadline', value: _shortDate(o.deadline!)),
          _Meta(label: 'Created', value: _shortDate(o.createdAt)),
        ]),
        if (o.status == 'disputed' &&
            o.disputeReason != null &&
            o.disputeReason!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AdminPalette.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AdminPalette.red.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Dispute reason',
                  style: TextStyle(
                      color: AdminPalette.red, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(o.disputeReason!,
                  style: const TextStyle(color: AdminPalette.textDim)),
            ]),
          ),
        ],
      ]),
    );
  }
}
