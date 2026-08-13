import 'package:flutter/material.dart';

import '../models/factory.dart';
import '../models/inventory_item.dart';
import '../theme.dart';
import 'brutal.dart';

/// Depot / Sleeper tab selector used by the Actions and Audit screens.
class SectionTabs extends StatelessWidget {
  final InventorySection active;
  final ValueChanged<InventorySection> onChanged;

  const SectionTabs({
    super.key,
    required this.active,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _tab(
            'Depot',
            active == InventorySection.depot,
            () => onChanged(InventorySection.depot),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _tab(
            'Sleeper',
            active == InventorySection.sleeper,
            () => onChanged(InventorySection.sleeper),
          ),
        ),
      ],
    );
  }

  Widget _tab(String label, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? kInk : kSurface,
          border: Border.all(color: kBorderDark, width: 1),
        ),
        child: MonoLabel(
          label,
          size: 11,
          weight: FontWeight.w600,
          color: isActive ? kSurface : kInk,
        ),
      ),
    );
  }
}

/// All / factory-name filter chips used under the Sleeper Actions & Audit.
class FactoryFilterChips extends StatelessWidget {
  final List<WarehouseFactory> factories;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const FactoryFilterChips({
    super.key,
    required this.factories,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip('ALL', selected == null, () => onChanged(null)),
        for (final factory in factories)
          _chip(
            factory.name,
            selected == factory.name,
            () => onChanged(factory.name),
          ),
      ],
    );
  }

  Widget _chip(String label, bool isActive, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? kInk : kSurface,
          border: Border.all(color: kBorderDark, width: 1),
        ),
        child: MonoLabel(
          label,
          size: 9,
          weight: FontWeight.w600,
          color: isActive ? kSurface : kInk,
        ),
      ),
    );
  }
}
