import 'package:flutter/material.dart';

import '../api/r2v_api.dart';
import 'widgets/admin_console_widgets.dart';
import 'widgets/admin_management_sections.dart';
import 'widgets/admin_reports_section.dart';
import 'widgets/admin_sections.dart';

class _AdminNavItem {
  const _AdminNavItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget Function(int refreshTick) builder;
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _index = 0;
  int _refreshTick = 0;
  String _role = 'admin';

  late List<_AdminNavItem> _items = _buildItems();

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  bool get _isSuperAdmin => _role == 'super_admin';

  Future<void> _loadRole() async {
    try {
      final me = await r2vAuth.me();
      final role = (me['role'] ?? 'admin').toString();
      if (!mounted) return;
      // Route guard: only admin / super_admin may stay on this console. A normal
      // user (or freelancer) is sent home. Authorization is still enforced
      // server-side; this just avoids showing the console shell to them.
      if (role != 'admin' && role != 'super_admin') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Admin access required.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        return;
      }
      setState(() {
        _role = role;
        _items = _buildItems();
        if (_index >= _items.length) _index = 0;
      });
    } catch (_) {
      // Keep base (non-super) items if /me is unavailable; server-side checks
      // still gate every admin endpoint.
    }
  }

  List<_AdminNavItem> _buildItems() {
    final items = <_AdminNavItem>[
      _AdminNavItem(
        title: 'System Overview',
        subtitle:
            'Monitoring R2V engine, marketplace, users, and platform health.',
        icon: Icons.dashboard_rounded,
        builder: (tick) => AdminOverviewSection(refreshTick: tick),
      ),
      _AdminNavItem(
        title: 'AI Generation',
        subtitle:
            'Monitor 3D generation jobs, queues, failures, and engine health.',
        icon: Icons.auto_awesome_rounded,
        builder: (tick) => AdminAiSection(refreshTick: tick),
      ),
      _AdminNavItem(
        title: 'Marketplace Console',
        subtitle:
            'Moderate assets — hide, restore, or remove any creator\'s upload.',
        icon: Icons.storefront_rounded,
        builder: (tick) => AdminAssetsManageSection(refreshTick: tick),
      ),
      _AdminNavItem(
        title: 'Directory',
        subtitle: 'Manage users — search, ban/unban, and roles.',
        icon: Icons.group_rounded,
        builder: (tick) => AdminUsersManageSection(
          refreshTick: tick,
          isSuperAdmin: _isSuperAdmin,
        ),
      ),
      _AdminNavItem(
        title: 'Freelancers',
        subtitle: 'Review freelancers, suspend or reactivate accounts.',
        icon: Icons.work_outline_rounded,
        builder: (tick) => AdminFreelancersManageSection(refreshTick: tick),
      ),
      _AdminNavItem(
        title: 'Freelancer Applications',
        subtitle:
            'Review, approve, and reject requests to become a freelancer.',
        icon: Icons.assignment_ind_rounded,
        builder: (tick) => AdminApplicationsSection(refreshTick: tick),
      ),
      _AdminNavItem(
        title: 'Freelance Services',
        subtitle: 'Moderate freelance services — hide, reject, or reactivate.',
        icon: Icons.design_services_rounded,
        builder: (tick) => AdminFreelanceServicesSection(refreshTick: tick),
      ),
      _AdminNavItem(
        title: 'Freelance Orders',
        subtitle: 'Monitor freelance orders, disputes, and operations metrics.',
        icon: Icons.receipt_long_rounded,
        builder: (tick) => AdminFreelanceOrdersSection(refreshTick: tick),
      ),
      _AdminNavItem(
        title: 'Reports / Moderation',
        subtitle:
            'Review user-submitted reports on assets, models, freelancers, and users.',
        icon: Icons.verified_user_rounded,
        builder: (tick) => AdminReportsSection(refreshTick: tick),
      ),
      _AdminNavItem(
        title: 'System Health',
        subtitle:
            'Monitor backend, AI pipeline, queue, storage, and availability.',
        icon: Icons.monitor_heart_rounded,
        builder: (tick) => AdminSystemSection(refreshTick: tick),
      ),
    ];

    if (_isSuperAdmin) {
      items.add(
        _AdminNavItem(
          title: 'Admins Management',
          subtitle:
              'Create, promote, and demote admins. Super admin only.',
          icon: Icons.admin_panel_settings_rounded,
          builder: (tick) => AdminManagementSection(refreshTick: tick),
        ),
      );
    }

    items.add(
      _AdminNavItem(
        title: 'Settings',
        subtitle: 'Console configuration and environment information.',
        icon: Icons.settings_rounded,
        builder: (tick) => AdminSettingsSection(refreshTick: tick),
      ),
    );
    return items;
  }

  void _refresh() => setState(() => _refreshTick++);

  void _select(int index) {
    if (_index == index) return;
    setState(() => _index = index);
  }

  Future<void> _logout() async {
    await r2vAuth.logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/signin', (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 980;
    final item = _items[_index];

    return Scaffold(
      backgroundColor: AdminPalette.bg0,
      drawer: isWide
          ? null
          : Drawer(
              backgroundColor: AdminPalette.bg1,
              child: SafeArea(child: _Sidebar(
                items: _items,
                selected: _index,
                onSelect: (i) {
                  Navigator.of(context).pop();
                  _select(i);
                },
                onLogout: _logout,
              )),
            ),
      body: Stack(
        children: [
          const Positioned.fill(child: AdminBackground()),
          SafeArea(
            child: Row(
              children: [
                if (isWide)
                  _Sidebar(
                    items: _items,
                    selected: _index,
                    onSelect: _select,
                    onLogout: _logout,
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(
                        item: item,
                        showMenu: !isWide,
                        onRefresh: _refresh,
                        isSuperAdmin: _isSuperAdmin,
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1240),
                            child: item.builder(_refreshTick),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.onLogout,
  });

  final List<_AdminNavItem> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 258,
      decoration: const BoxDecoration(
        color: Color(0xFF0E0A18),
        border: Border(right: BorderSide(color: AdminPalette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AdminPalette.violet, AdminPalette.pink],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.bubble_chart_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'R2V Admin',
                      style: TextStyle(
                        color: AdminPalette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Terminal v1.0.0',
                      style: TextStyle(
                        color: AdminPalette.textDim,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: items.length,
              itemBuilder: (context, i) => _NavTile(
                item: items[i],
                active: i == selected,
                onTap: () => onSelect(i),
              ),
            ),
          ),
          const Divider(color: AdminPalette.border, height: 1),
          _BottomAction(
            icon: Icons.logout_rounded,
            label: 'Logout',
            color: AdminPalette.red,
            onTap: onLogout,
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active, required this.onTap});

  final _AdminNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: active ? AdminPalette.violet.withOpacity(0.16) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? AdminPalette.violet.withOpacity(0.4) : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  size: 20,
                  color: active ? AdminPalette.violet : AdminPalette.textDim,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? AdminPalette.text : AdminPalette.textDim,
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomAction extends StatelessWidget {
  const _BottomAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.item,
    required this.showMenu,
    required this.onRefresh,
    required this.isSuperAdmin,
  });

  final _AdminNavItem item;
  final bool showMenu;
  final VoidCallback onRefresh;
  final bool isSuperAdmin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showMenu)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2),
              child: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded, color: AdminPalette.text),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: const TextStyle(
                    color: AdminPalette.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.subtitle,
                  style: const TextStyle(
                    color: AdminPalette.textDim,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _AdminBadge(isSuperAdmin: isSuperAdmin),
          const SizedBox(width: 10),
          _RefreshButton(onRefresh: onRefresh),
        ],
      ),
    );
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge({required this.isSuperAdmin});

  final bool isSuperAdmin;

  @override
  Widget build(BuildContext context) {
    final color = isSuperAdmin ? AdminPalette.amber : AdminPalette.violet;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSuperAdmin
                ? Icons.workspace_premium_rounded
                : Icons.shield_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 7),
          Text(
            isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN',
            style: TextStyle(
              color: color,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshButton extends StatelessWidget {
  const _RefreshButton({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onRefresh,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AdminPalette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.refresh_rounded, size: 17, color: AdminPalette.text),
              SizedBox(width: 8),
              Text(
                'Refresh',
                style: TextStyle(
                  color: AdminPalette.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
