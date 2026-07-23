/// A user the admin can request on behalf of.
class SeerrUser {
  final int id;
  final String name;
  final String? email;
  final String? avatarUrl; // resolved to a full URL
  const SeerrUser(
      {required this.id, required this.name, this.email, this.avatarUrl});
}

/// A quality (or language) profile from the connected Radarr/Sonarr.
class SeerrProfile {
  final int id;
  final String name;
  const SeerrProfile({required this.id, required this.name});
}

/// A Radarr/Sonarr root folder.
class SeerrRootFolder {
  final int id;
  final String path;
  const SeerrRootFolder({required this.id, required this.path});
}

/// A Radarr/Sonarr tag.
class SeerrTag {
  final int id;
  final String label;
  const SeerrTag({required this.id, required this.label});
}

/// One arr server behind the Seerr instance.
class SeerrServer {
  final int id;
  final String name;
  final bool is4k;
  final bool isDefault;
  const SeerrServer({
    required this.id,
    required this.name,
    this.is4k = false,
    this.isDefault = false,
  });
}

/// The per-server advanced options: quality profiles, root folders, tags, and
/// (for Sonarr) language profiles, with the server's active defaults.
class SeerrServerOptions {
  final List<SeerrProfile> profiles;
  final int? defaultProfileId;
  final List<SeerrRootFolder> rootFolders;
  final String? defaultRootFolder;
  final List<SeerrTag> tags;
  final List<SeerrProfile> languageProfiles;
  final int? defaultLanguageProfileId;
  const SeerrServerOptions({
    this.profiles = const [],
    this.defaultProfileId,
    this.rootFolders = const [],
    this.defaultRootFolder,
    this.tags = const [],
    this.languageProfiles = const [],
    this.defaultLanguageProfileId,
  });

  static const empty = SeerrServerOptions();
}
