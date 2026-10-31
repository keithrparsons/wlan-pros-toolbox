// MyToolsItem — one entry My Tools can hold: a catalog tool, or an Educational
// Resources entry (Keith, 2026-10-09: "yes, make them addable", after Ferney's
// beta report that nothing in Educational Resources could be added).
//
// Three kinds, one stored id each, all in the controller's single
// shared_preferences list:
//   * a catalog tool: its `ToolEntry.id`, unchanged, so lists saved before
//     this change load exactly as they did;
//   * an online resource from assets/data/educational_resources.json:
//     `resource:<id>`. The prefix keeps the resource ids out of the tool id
//     space for good, not just today (no collision as of 2026-10-09);
//   * the in-app Field Manual, the directory's "In-Depth Guide" row:
//     `guide:field-manual`.
// Ham Radio Study Resources, the directory's one reference card, is a catalog
// tool and is stored as one.
//
// Opening an item goes to the same place tapping it in Educational Resources
// goes: the tool's route, the resource's detail screen, or the Field Manual
// reader.
//
// The resource list is a bundled asset, so [MyToolsResources] reads it once
// before My Tools loads (main.dart). Until it has loaded, a `resource:` id is
// kept rather than dropped: a failed or late asset read must never delete what
// the user saved.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/tool_catalog.dart';
import '../screens/guides/guide_reader_screen.dart';
import '../screens/tools/educational/educational_resource_detail_screen.dart';
import '../screens/tools/educational/educational_resources_screen.dart'
    show kEducationalResourcesAsset;
import '../services/educational/educational_resources_service.dart';

/// The stored-id prefix for an online Educational Resources entry.
const String kMyToolsResourcePrefix = 'resource:';

/// The stored id of the in-app Field Manual.
const String kMyToolsFieldManualId = 'guide:field-manual';

/// The stored id for the resource with [resourceId].
String myToolsResourceId(String resourceId) =>
    '$kMyToolsResourcePrefix$resourceId';

/// What an item is, which decides how it opens and which icon it shows.
enum MyToolsItemKind { tool, resource, fieldManual }

/// One entry in My Tools.
class MyToolsItem {
  const MyToolsItem._({
    required this.id,
    required this.title,
    required this.kind,
    this.tool,
    this.resource,
  });

  /// A catalog tool, stored under its own id.
  factory MyToolsItem.tool(ToolEntry tool) => MyToolsItem._(
    id: tool.id,
    title: tool.title,
    kind: MyToolsItemKind.tool,
    tool: tool,
  );

  /// An online Educational Resources entry.
  factory MyToolsItem.resource(EducationalResource resource) => MyToolsItem._(
    id: myToolsResourceId(resource.id),
    title: resource.title,
    kind: MyToolsItemKind.resource,
    resource: resource,
  );

  /// The in-app Field Manual. Its title is the directory row's.
  static const MyToolsItem fieldManual = MyToolsItem._(
    id: kMyToolsFieldManualId,
    title: 'Field Manual',
    kind: MyToolsItemKind.fieldManual,
  );

  /// The id stored in the controller's list.
  final String id;

  /// The title shown on the My Tools tile and in its dialogs.
  final String title;

  final MyToolsItemKind kind;

  /// Set for [MyToolsItemKind.tool].
  final ToolEntry? tool;

  /// Set for [MyToolsItemKind.resource].
  final EducationalResource? resource;

  /// Opens the item where Educational Resources (or a tool list) opens it.
  void open(BuildContext context) {
    switch (kind) {
      case MyToolsItemKind.tool:
        Navigator.of(context).pushNamed(tool!.routeName);
      case MyToolsItemKind.resource:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                EducationalResourceDetailScreen(resource: resource!),
          ),
        );
      case MyToolsItemKind.fieldManual:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const GuideReaderScreen(
              assetPath: kFieldManualAsset,
              title: 'Field Manual',
            ),
          ),
        );
    }
  }
}

/// The item stored under [id] on this platform, or null when this build does
/// not carry it (or, for a resource, when the resource list has not loaded).
MyToolsItem? myToolsItemById(String id) {
  if (id == kMyToolsFieldManualId) return MyToolsItem.fieldManual;
  if (id.startsWith(kMyToolsResourcePrefix)) {
    final EducationalResource? r = MyToolsResources.instance.byId(
      id.substring(kMyToolsResourcePrefix.length),
    );
    return r == null ? null : MyToolsItem.resource(r);
  }
  for (final ToolCategory c in kToolCategories) {
    for (final ToolEntry t in c.tools) {
      if (t.id == id) return MyToolsItem.tool(t);
    }
  }
  return null;
}

/// Whether [id] may stay in a loaded My Tools list. A resource id is kept
/// while the resource list is not loaded, so a failed asset read drops
/// nothing; once it has loaded, a resource the build no longer carries is
/// dropped like a retired tool.
bool myToolsIdIsKnown(String id) {
  if (id.startsWith(kMyToolsResourcePrefix) &&
      !MyToolsResources.instance.isLoaded) {
    return true;
  }
  return myToolsItemById(id) != null;
}

/// The online Educational Resources entries, by id, for resolving stored
/// `resource:` ids. Loaded once from the bundled asset before My Tools loads.
class MyToolsResources {
  MyToolsResources._();

  static final MyToolsResources instance = MyToolsResources._();

  Map<String, EducationalResource>? _byId;

  bool get isLoaded => _byId != null;

  EducationalResource? byId(String id) => _byId?[id];

  /// Reads assets/data/educational_resources.json. Never throws: on failure
  /// the list stays unloaded and stored resource ids are kept, not dropped.
  Future<void> load() async {
    try {
      final String raw = await rootBundle.loadString(
        kEducationalResourcesAsset,
      );
      use(EducationalResourcesService.fromJson(raw).all);
    } catch (_) {
      // Asset unreadable: leave unloaded.
    }
  }

  /// Sets the entries directly. Used by [load] and by tests.
  void use(Iterable<EducationalResource> entries) {
    _byId = <String, EducationalResource>{
      for (final EducationalResource r in entries) r.id: r,
    };
  }

  /// Back to unloaded. Tests only.
  @visibleForTesting
  void reset() => _byId = null;
}
