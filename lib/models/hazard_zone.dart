// =============================================================================
// HazardZone
// -----------------------------------------------------------------------------
// Location zone selected by the user at capture time. Becomes one of the 5
// structured fields the Gemini service feeds to the LLM so the recommendation
// can be tailored to where the hazard was found (e.g. "in a sports facility"
// vs "in a public area").
//
// "Unspecified" is the default — included as an explicit value so the user
// can deliberately skip the zone choice without us having to encode that as
// a separate null state.
// =============================================================================

import 'package:flutter/material.dart';

enum HazardZone {
  unspecified(
    displayName: 'Unspecified',
    icon: Icons.help_outline,
  ),
  publicFacilities(
    displayName: 'Public Facilities',
    icon: Icons.apartment,
  ),
  sportsFacilities(
    displayName: 'Sports Facilities',
    icon: Icons.sports_basketball,
  ),
  campusPark(
    displayName: 'Campus Park',
    icon: Icons.park,
  );

  /// Human-readable label shown in the zone picker AND fed verbatim into the
  /// Gemini prompt so the LLM sees the same wording the user saw.
  final String displayName;

  /// Material icon shown next to the label in the picker.
  final IconData icon;

  const HazardZone({required this.displayName, required this.icon});
}
