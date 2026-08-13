import 'package:flutter/material.dart';

import '../theme.dart';

/// A card with a hard 1px dark border (the `.brutal-border` utility).
class BrutalCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool borderTopOnly;

  const BrutalCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = kSurface,
    this.borderTopOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        border: Border(
          top: const BorderSide(color: kBorderDark, width: 1),
          left: borderTopOnly
              ? BorderSide.none
              : const BorderSide(color: kBorderDark, width: 1),
          right: borderTopOnly
              ? BorderSide.none
              : const BorderSide(color: kBorderDark, width: 1),
          bottom: borderTopOnly
              ? BorderSide.none
              : const BorderSide(color: kBorderDark, width: 1),
        ),
      ),
      padding: padding,
      child: child,
    );
  }
}

/// A bordered button (`.brutal-btn`). White bg by default, inverts to black
/// on hover/press; pass [filled] for a black button with white text.
class BrutalButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double iconSize;
  final bool filled;
  final TextStyle? labelStyle;
  final EdgeInsetsGeometry padding;

  const BrutalButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.iconSize = 20,
    this.filled = false,
    this.labelStyle,
    this.padding = const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? kInk : kSurface,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: kInk, width: 1)),
          padding: padding,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: iconSize, color: filled ? kSurface : kInk),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: labelStyle ??
                    monoStyle(
                      size: 12,
                      weight: FontWeight.w700,
                      color: filled ? kSurface : kInk,
                      letterSpacing: 1.5,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A brutalist text field (`.brutal-input`): hard 1px black border that gains
/// the 2px 2px hard offset shadow on focus, matching the Tailwind utility.
class BrutalTextInput extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final TextInputType keyboardType;
  final bool obscureText;
  final int maxLines;
  final bool uppercase;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextAlign textAlign;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;
  final EdgeInsetsGeometry contentPadding;
  final double minHeight;

  const BrutalTextInput({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.maxLines = 1,
    this.uppercase = false,
    this.prefixIcon,
    this.suffixIcon,
    this.textAlign = TextAlign.start,
    this.onChanged,
    this.textInputAction,
    this.contentPadding =
        const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    this.minHeight = 44,
  });

  @override
  State<BrutalTextInput> createState() => _BrutalTextInputState();
}

class _BrutalTextInputState extends State<BrutalTextInput> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: monoStyle(weight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color: kSurface,
            border: Border.all(color: kBorderDark, width: 1),
            boxShadow: _focused
                ? const [BoxShadow(offset: Offset(2, 2), color: kBorderDark)]
                : null,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: widget.minHeight),
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              keyboardType: widget.keyboardType,
              obscureText: widget.obscureText,
              maxLines: widget.maxLines,
              textCapitalization: widget.uppercase
                  ? TextCapitalization.characters
                  : TextCapitalization.none,
              textAlign: widget.textAlign,
              onChanged: widget.onChanged,
              textInputAction: widget.textInputAction,
              style: monoStyle(size: 13, color: kInk),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: widget.hint,
                hintStyle: monoStyle(color: kGray400),
                prefixIcon: widget.prefixIcon,
                suffixIcon: widget.suffixIcon,
                contentPadding: widget.contentPadding,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Form-field variant of [BrutalTextInput] with label + validator support.
class BrutalTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType keyboardType;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final TextInputAction? textInputAction;

  const BrutalTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.validator,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.onChanged,
    this.textInputAction,
  });

  @override
  State<BrutalTextField> createState() => _BrutalTextFieldState();
}

class _BrutalTextFieldState extends State<BrutalTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: monoStyle(weight: FontWeight.w600)),
          const SizedBox(height: 8),
        ],
        Container(
          decoration: BoxDecoration(
            color: kSurface,
            border: Border.all(color: kBorderDark, width: 1),
            boxShadow: _focused
                ? const [BoxShadow(offset: Offset(2, 2), color: kBorderDark)]
                : null,
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            validator: widget.validator,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            textInputAction: widget.textInputAction,
            style: monoStyle(size: 13, color: kInk),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: monoStyle(color: kGray400),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dashed border wrapper (React `border-dashed`), painted on all four sides.
class DashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double width;
  final double dash;
  final double gap;
  final EdgeInsetsGeometry padding;

  const DashedBorder({
    super.key,
    required this.child,
    this.color = kGray300,
    this.width = 1,
    this.dash = 5,
    this.gap = 3,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: color,
        width: width,
        dash: dash,
        gap: gap,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double width;
  final double dash;
  final double gap;

  _DashedBorderPainter({
    required this.color,
    required this.width,
    required this.dash,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path();
    _dash(canvas, paint, Offset.zero, Offset(size.width, 0), path);
    _dash(canvas, paint, Offset(size.width, 0), Offset(size.width, size.height), path);
    _dash(canvas, paint, Offset(size.width, size.height), Offset(0, size.height), path);
    _dash(canvas, paint, Offset(0, size.height), Offset.zero, path);
  }

  void _dash(Canvas canvas, Paint paint, Offset a, Offset b, Path path) {
    final total = (b - a).distance;
    var t = 0.0;
    while (t < total) {
      path.moveTo(Offset.lerp(a, b, t / total)!.dx, Offset.lerp(a, b, t / total)!.dy);
      path.lineTo(
          Offset.lerp(a, b, (t + dash) / total)!.dx,
          Offset.lerp(a, b, (t + dash) / total)!.dy);
      t += dash + gap;
    }
    canvas.drawPath(path, paint);
    path.reset();
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) {
    return old.color != color ||
        old.width != width ||
        old.dash != dash ||
        old.gap != gap;
  }
}

/// Mono, uppercase label with wide tracking (`.font-mono uppercase tracking-widest`).
class MonoLabel extends StatelessWidget {
  final String text;
  final double size;
  final FontWeight weight;
  final Color color;

  const MonoLabel(
    this.text, {
    super.key,
    this.size = 10,
    this.weight = FontWeight.w400,
    this.color = kInkMuted,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: monoStyle(
        size: size,
        weight: weight,
        color: color,
        letterSpacing: 0.9,
      ),
    );
  }
}

/// Centers content on a max-width column (React `max-w-3xl mx-auto`).
class MaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const MaxWidth({
    super.key,
    required this.child,
    this.maxWidth = 768,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
