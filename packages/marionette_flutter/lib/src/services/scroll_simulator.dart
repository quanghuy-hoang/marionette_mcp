import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:marionette_flutter/src/binding/marionette_configuration.dart';
import 'package:marionette_flutter/src/services/gesture_dispatcher.dart';
import 'package:marionette_flutter/src/services/widget_finder.dart';
import 'package:marionette_flutter/src/services/widget_matcher.dart';

/// Simulates scrolling gestures to make widgets visible.
class ScrollSimulator {
  const ScrollSimulator(this._gestureDispatcher, this._widgetFinder);

  final GestureDispatcher _gestureDispatcher;
  final WidgetFinder _widgetFinder;

  static const _delta = 64.0;
  static const _maxScrolls = 50;

  /// Scrolls until the widget matching [matcher] is visible.
  ///
  /// Uses two strategies:
  /// 1. If the target is already in the widget tree (e.g., inside a
  ///    [SingleChildScrollView] which builds all children), uses
  ///    [Scrollable.ensureVisible] for reliable, direct scrolling.
  /// 2. If the target is not yet built (e.g., in a [ListView] with lazy
  ///    building), falls back to simulated drag gestures on the first
  ///    [Scrollable] in the tree.
  ///
  /// Throws an [Exception] if:
  /// - No [Scrollable] widget is found in the tree
  /// - The target widget is not visible after [_maxScrolls] scroll attempts
  Future<void> scrollUntilVisible(
    WidgetMatcher matcher,
    MarionetteConfiguration configuration,
  ) async {
    // Strategy 1: If the target is already in the tree, use ensureVisible.
    // This is the most reliable approach and works correctly with nested
    // scroll views (e.g., sidebar + main content area).
    final target = _widgetFinder.findElement(matcher, configuration);

    if (target != null) {
      final renderObject = target.renderObject;
      if (renderObject != null) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
        // Wait for the scroll animation to complete and frame to settle
        await Future<void>.delayed(const Duration(milliseconds: 350));

        // Verify the target is now hittable
        if (_isHittable(target)) {
          return;
        }
      }
    }

    // Strategy 2: Fall back to drag-based scrolling.
    // Needed for ListView/GridView where off-screen children aren't built.
    final scrollable = _widgetFinder.findElement(
      const TypeMatcher(Scrollable),
      configuration,
    );

    if (scrollable == null) {
      throw Exception('No Scrollable widget found in the tree');
    }

    // Get the scroll direction
    final scrollableWidget = scrollable.widget as Scrollable;
    final direction = scrollableWidget.axisDirection;

    // Calculate move step based on direction
    final moveStep = switch (direction) {
      AxisDirection.up => const Offset(0, _delta),
      AxisDirection.down => const Offset(0, -_delta),
      AxisDirection.left => const Offset(_delta, 0),
      AxisDirection.right => const Offset(-_delta, 0),
    };

    // Scroll until visible
    await _dragUntilVisible(matcher, scrollable, moveStep, configuration);
  }

  /// Repeatedly drags the scrollable until the target is visible.
  Future<void> _dragUntilVisible(
    WidgetMatcher targetMatcher,
    Element scrollable,
    Offset moveStep,
    MarionetteConfiguration configuration,
  ) async {
    for (var i = 0; i < _maxScrolls; i++) {
      // Find the target element
      final target = _widgetFinder.findElement(targetMatcher, configuration);
      // Check if target is visible
      if (target != null && _isHittable(target)) {
        return;
      }

      final renderObject = scrollable.renderObject;
      if (renderObject is! RenderBox) {
        throw Exception('Scrollable does not have a RenderBox');
      }

      final center = renderObject.size.center(Offset.zero);
      final globalPosition = renderObject.localToGlobal(center);

      final to = globalPosition + moveStep;
      await _gestureDispatcher.drag(globalPosition, to);
    }

    // Target still not visible after max scrolls
    throw StateError('Widget not found after $_maxScrolls scroll attempts');
  }

  /// Checks if the element is hittable (i.e., can receive pointer events).
  ///
  /// Performs a hit test at the center of the element to determine if it's
  /// actually interactive, not just within viewport bounds.
  bool _isHittable(Element element) {
    final renderObject = element.renderObject;
    if (renderObject is! RenderBox) {
      return false;
    }

    if (!renderObject.hasSize) {
      return false;
    }

    // Get the view ID from the ancestor View widget
    final view = element.findAncestorWidgetOfExactType<View>();
    if (view == null) {
      return false;
    }
    final viewId = view.view.viewId;

    // Calculate the center position of the element
    final center = renderObject.size.center(Offset.zero);
    final absoluteOffset = renderObject.localToGlobal(center);

    // Perform hit test at the center of the element
    final hitResult = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hitResult, absoluteOffset, viewId);

    // Check if the element's render object is in the hit test path
    for (final entry in hitResult.path) {
      if (entry.target == renderObject) {
        return true;
      }
    }

    return false;
  }
}
