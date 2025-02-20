import 'package:atproto/atproto.dart' as at;
import 'package:atproto/atproto.dart';
import 'package:bluesky/bluesky.dart' as bsky;
import 'package:collection/collection.dart';
import 'package:copy_with_extension/copy_with_extension.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:sky_bridge/database.dart';
import 'package:sky_bridge/facets.dart';
import 'package:sky_bridge/models/database/post_record.dart';
import 'package:sky_bridge/models/database/repost_record.dart';
import 'package:sky_bridge/models/mastodon/mastodon_account.dart';
import 'package:sky_bridge/models/mastodon/mastodon_card.dart';
import 'package:sky_bridge/models/mastodon/mastodon_media_attachment.dart';
import 'package:sky_bridge/models/mastodon/mastodon_mention.dart';
import 'package:sky_bridge/util.dart';

part 'mastodon_post.g.dart';

/// Representation for a Mastodon status.
@JsonSerializable()
@CopyWith()
class MastodonPost {
  /// Constructs an instance of [MastodonPost].
  MastodonPost({
    required this.id,
    required this.createdAt,
    required this.sensitive,
    required this.spoilerText,
    required this.visibility,
    required this.uri,
    required this.repliesCount,
    required this.reblogsCount,
    required this.favouritesCount,
    required this.content,
    required this.account,
    required this.mediaAttachments,
    required this.mentions,
    required this.tags,
    required this.emojis,
    required this.application,
    required this.filtered,
    this.inReplyToId,
    this.inReplyToAccountId,
    this.language,
    this.url,
    this.favourited,
    this.reblogged,
    this.muted,
    this.bookmarked,
    this.reblog,
    this.card,
    this.poll,
    this.text,
    this.editedAt,
    this.pinned,
    this.replyPostUri,
  });

  /// Converts JSON into a [MastodonPost] instance.
  factory MastodonPost.fromJson(Map<String, dynamic> json) =>
      _$MastodonPostFromJson(json);

  /// Converts the [MastodonPost] to JSON.
  Map<String, dynamic> toJson() => _$MastodonPostToJson(this);

  /// Converts a [bsky.FeedView] to a [MastodonPost].
  static Future<MastodonPost> fromFeedView(bsky.FeedView view) async {
    final post = view.post;
    final isRepost = view.reason?.type.endsWith('reasonRepost') ?? false;

    // Process facets such as mentions and links.
    final processed = await processFacets(
      view.post.record.facets ?? [],
      post.record.text,
    );

    // Bit of a mess right now, could use some cleaning up...
    MastodonAccount account;
    var id = (await postToDatabase(post)).id;
    var content = processed.htmlText;
    var text = post.record.text;
    var likeCount = post.likeCount;
    var repostCount = post.repostCount;
    var replyCount = post.replyCount;
    final mediaAttachments = <MastodonMediaAttachment>[];
    String? language = 'en';

    // Handle embedded content.
    if (post.embed != null) {
      if (post.embed!.data is bsky.EmbedViewImages) {
        final embed = post.embed!.data as bsky.EmbedViewImages;
        // Convert the embed to a media attachment.
        for (final image in embed.images) {
          final attachment = MastodonMediaAttachment.fromEmbed(image);
          mediaAttachments.add(attachment);
        }
      }
    }

    if (isRepost) {
      // Clear out the content, since this is a repost.
      content = '';
      text = '';
      likeCount = 0;
      repostCount = 0;
      replyCount = 0;
      language = null;
      mediaAttachments.clear();

      // Since this is a repost, we need to assign a unique ID and get
      // the account that reposted it.
      id = (await repostToDatabase(view)).id;
      account = await MastodonAccount.fromActor(view.reason!.by);
    } else {
      account = await MastodonAccount.fromActor(post.author);
    }

    // Construct URL/URI
    // will need to change this when federation is a thing probably?
    final postId = post.uri.toString().split('/').last;
    const base = 'https://bsky.app';
    final url = '$base/profile/${account.username}/post/$postId';

    final card = MastodonCard.fromEmbed(post.embed);

    return MastodonPost(
      id: id.toString(),
      createdAt: post.indexedAt.toUtc(),
      sensitive: false,
      spoilerText: '',
      visibility: PostVisibility.public,
      language: language,
      uri: url,
      url: url,
      repliesCount: replyCount,
      reblogsCount: repostCount,
      favouritesCount: likeCount,
      favourited: post.viewer.like != null,
      reblogged: post.viewer.repost != null,
      muted: false,
      bookmarked: false,
      content: '<p>$content</p>',
      text: text,
      reblog: isRepost ? await MastodonPost.fromBlueSkyPost(view.post) : null,
      application: {
        'name': 'BlueSky',
        'website': '',
      },
      account: account,
      mediaAttachments: mediaAttachments,
      mentions: processed.mentions,
      tags: [],
      emojis: [],
      pinned: false,
      filtered: [],
      card: card,
      replyPostUri: view.post.record.reply?.parent.uri,
    );
  }

  /// Converts a [bsky.Post] to a [MastodonPost].
  static Future<MastodonPost> fromBlueSkyPost(bsky.Post post) async {
    final mediaAttachments = <MastodonMediaAttachment>[];
    final account = await MastodonAccount.fromActor(post.author);

    if (post.embed != null) {
      if (post.embed!.data is bsky.EmbedViewImages) {
        final embed = post.embed!.data as bsky.EmbedViewImages;
        // Convert the embed to a media attachment.
        for (final image in embed.images) {
          final attachment = MastodonMediaAttachment.fromEmbed(image);
          mediaAttachments.add(attachment);
        }
      }
    }

    // Process facets such as mentions and links.
    final processed = await processFacets(
      post.record.facets ?? [],
      post.record.text,
    );

    // Construct URL/URI
    // will need to change this when federation is a thing probably?
    final postId = post.uri.toString().split('/').last;
    const base = 'https://bsky.app';
    final url = '$base/profile/${account.username}/post/$postId';

    final card = MastodonCard.fromEmbed(post.embed);

    return MastodonPost(
      id: (await postToDatabase(post)).id.toString(),
      createdAt: post.indexedAt.toUtc(),
      sensitive: false,
      spoilerText: '',
      visibility: PostVisibility.public,
      language: 'en',
      uri: url,
      url: url,
      repliesCount: post.replyCount,
      reblogsCount: post.repostCount,
      favouritesCount: post.likeCount,
      favourited: post.viewer.like != null,
      reblogged: post.viewer.repost != null,
      muted: false,
      bookmarked: false,
      content: '<p>${processed.htmlText}</p>',
      text: post.record.text,
      application: {
        'name': 'BlueSky',
        'website': '',
      },
      account: account,
      mediaAttachments: mediaAttachments,
      mentions: processed.mentions,
      tags: [],
      emojis: [],
      pinned: false,
      filtered: [],
      card: card,
      replyPostUri: post.record.reply?.parent.uri,
    );
  }

  /// Uses the current user session to repost this [MastodonPost].
  Future<MastodonPost?> repost(bsky.Bluesky bluesky) async {
    // Convert the string ID to an int and get the record for the post.
    final intId = int.parse(id);
    final postRecord = await db.postRecords.get(intId);
    if (postRecord != null) {
      late RepostRecord repostRecord;
      final createdAt = DateTime.now().toUtc();

      // Create the appropriate bluesky record.
      await bluesky.repositories.createRecord(
        collection: at.NSID.create('feed.bsky.app', 'repost'),
        record: {
          'subject': {
            'cid': postRecord.cid,
            'uri': postRecord.uri,
          },
          'createdAt': createdAt.toIso8601String(),
        },
      );

      // Write the repost to the database.
      await db.writeTxn(() async {
        repostRecord = await postRecord.repost(createdAt, postRecord.author);
      });

      final repost = copyWith(
        id: repostRecord.id.toString(),
        content: '',
        text: '',
        favouritesCount: 0,
        reblogsCount: 0,
        repliesCount: 0,
        language: null,
        reblog: this,
        reblogged: true,
        createdAt: createdAt,
      )..reblogsCount += 1;

      return repost;
    }
    return null;
  }

  /// The ID of the post. Is a 64-bit integer cast to a string.
  final String id;

  /// URI of the status used for federation.
  final String uri;

  /// The date when this post was created.
  @JsonKey(
    name: 'created_at',
    fromJson: dateTimeFromISO8601,
    toJson: dateTimeToISO8601,
  )
  final DateTime createdAt;

  /// The account that authored this post.
  final MastodonAccount account;

  /// HTML-encoded post content.
  final String content;

  /// Visibility of this post.
  final PostVisibility visibility;

  /// Whether this post is marked as sensitive.
  final bool sensitive;

  /// Subject or summary line, below which post content is collapsed
  /// until expanded.
  @JsonKey(name: 'spoiler_text')
  final String spoilerText;

  /// Media that is attached to this post.
  @JsonKey(name: 'media_attachments')
  final List<MastodonMediaAttachment> mediaAttachments;

  /// The application used to create this post.
  final Map<String, String?> application;

  /// Mentions of users within the post content.
  final List<MastodonMention> mentions;

  /// Hashtags used within the post content.
  /// Bluesky has no concept of hashtags at the moment so this is always empty.
  final List<Map<String, dynamic>> tags;

  /// Custom emoji to be used when rendering the post content.
  final List<Map<String, dynamic>> emojis;

  /// How many reposts this post has received.
  @JsonKey(name: 'reblogs_count')
  int reblogsCount;

  /// How many likes this post has received.
  @JsonKey(name: 'favourites_count')
  int favouritesCount;

  /// How many replies this post has received.
  @JsonKey(name: 'replies_count')
  final int repliesCount;

  /// A link to the post's HTML representation.
  final String? url;

  /// The ID of the post this post is a reply to.
  @JsonKey(name: 'in_reply_to_id')
  String? inReplyToId;

  /// The 64-bit ID of the account this post is a reply to.
  @JsonKey(name: 'in_reply_to_account_id')
  String? inReplyToAccountId;

  /// The post being reblogged.
  final MastodonPost? reblog;

  /// The poll attached to this post.
  final Map<String, dynamic>? poll;

  /// Preview card for links included in the post content.
  final MastodonCard? card;

  /// Primary language of this post.
  final String? language;

  /// Plain-text source of a status. Returned instead of content when status
  /// is deleted, so the user may redraft from the source text without the
  /// client having to reverse-engineer the original text from the HTML content.
  final String? text;

  /// Timestamp of when the post was last edited.
  @JsonKey(
    name: 'edited_at',
    fromJson: dateTimeFromISO8601,
    toJson: dateTimeToISO8601,
  )
  final DateTime? editedAt;

  /// Whether the current user has liked this post.
  bool? favourited;

  /// Whether the current user has reblogged this post.
  bool? reblogged;

  /// Whether the current user h§as muted notifications for this post.
  final bool? muted;

  /// Whether the current user has bookmarked this post.
  final bool? bookmarked;

  /// Whether this post is pinned by the current user.
  final bool? pinned;

  /// The filter and keywords used to match this post by the current user.
  final List<String> filtered;

  /// The URI of the post this post is a reply to.
  /// Is not included in the JSON representation of a post, only used
  /// internally for [processParentPosts].
  @JsonKey(includeFromJson: false, includeToJson: false)
  final bsky.AtUri? replyPostUri;
}

/// The visibility of a post.
/// This is very Mastodon specific and currently doesn't mean much for Bluesky.
/// It is included for completeness, maybe this'll change in the future.
enum PostVisibility {
  /// Visible to everyone, shown on public timelines.
  @JsonValue('public')
  public,

  /// Visible to public, but not included in public timelines.
  @JsonValue('unlisted')
  unlisted,

  /// Visible to followers only, and to any mentioned users.
  @JsonValue('private')
  private,

  /// Visible only to mentioned users.
  @JsonValue('direct')
  direct,
}

/// Processes the parent posts of the given posts.
/// This is used to fetch the parent posts of a list of posts by their URIs.
Future<List<MastodonPost>> processParentPosts(
  bsky.Bluesky bluesky,
  List<MastodonPost> posts,
) async {
  // Collect all the CIDs of the posts we need to fetch.
  final uris = <bsky.AtUri>[];
  for (final post in posts) {
    final uri = post.replyPostUri;
    if (uri != null) {
      if (!uris.contains(uri)) uris.add(uri);
    }
  }

  // Pull the posts from the server in chunks to avoid hitting the
  // maximum post limit.
  final results = await chunkResults<bsky.Post, bsky.AtUri>(
    items: uris,
    callback: (chunk) async {
      final response = await bluesky.feeds.findPosts(uris: chunk);
      return response.data.posts;
    },
  );

  // Map the results back to the original posts.
  final modifiedPosts = <MastodonPost>[];
  await db.writeTxn(() async {
    for (final post in posts) {
      final uri = post.replyPostUri;
      if (uri != null) {
        final replyPost = results.firstWhereOrNull((post) {
          return post.uri.toString() == uri.toString();
        });
        if (replyPost != null) {
          final reply = await MastodonPost.fromBlueSkyPost(replyPost);
          post
            ..inReplyToId = reply.id
            ..inReplyToAccountId = reply.account.id;
        }
      }
      modifiedPosts.add(post);
    }
  });

  return modifiedPosts;
}
