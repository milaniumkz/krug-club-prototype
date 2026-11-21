# App Review — 2.4.0 (22)

## Purpose and audience

QMET+ is a trade-union member benefits service. The member app provides a digital membership card, participating venue and benefit information, favorites, a map, QR verification, usage history, support and notifications. QMET+ Partner is the companion app for approved participating businesses: venue and benefit management, banners, QR display, moderation notifications and usage summaries. These are benefits relating to physical venues and services, not digital content purchases. Neither app processes payments, sells subscriptions or contains paid digital features.

Public download is requested for both apps. Access to member benefits requires an eligible account supplied by a participating organization; partner access requires approval by the operator. There is no self-service account registration in either app. These are not tools for employee HR management, banking, investment or medical services.

## Reviewer access

Use the permanent credentials in the App Review Information username/password fields. Member username: `QMETREVIEW2026`; partner username: `qmet-review-partner-2026`. No invitation, SMS, purchase or organization-code entry is needed in the submitted native login screens. If another client requests an organization code, use `STORE_REVIEW`.

After the first successful sign-in, create and confirm your own six-digit device-local PIN. On subsequent launches enter that PIN. It is not an SMS code and is not supplied by the operator. If forgotten, use the sign-in-again option and the supplied credentials. Biometric access is optional. Camera, location and notification permissions can be denied without preventing browsing.

The accounts use an isolated demonstration organization and venue. Demo offers are clearly labeled and do not promise real discounts. No personal membership details or real-user records are needed for review.

## Typical flows

Member: launch → sign in → set local PIN → home/membership card → catalogue → demo venue and benefit details → save favorite → map → notifications → profile, history and support. Profile contains a personal-data deletion request; it is routed to the operator for handling. Account creation is not offered in the app.

Partner: launch → sign in → set local PIN → overview → venues → demo venue details/edit form and QR → banners → notifications → profile/support. Partner submissions are moderated by the operator before publication. There is no public social feed, public chat or member-to-member content publishing. Support messages are private; members can report problematic venue content through support. Moderators can reject content and disable partner access.

## Services and regional behavior

Core data and authentication use the operator's HTTPS REST API and PostgreSQL database; passwords are verified by that backend. Native sessions/PIN are stored using the device's protected storage. Firebase Cloud Messaging and Apple APNs deliver optional push notifications. Maps use OpenFreeMap/OpenStreetMap data; the device camera supports QR scanning and the system photo picker supports partner images. No social sign-in, AI service, payment gateway or advertising identifier SDK is used for core functionality.

Features operate consistently across enabled storefronts. Russian and Kazakh UI languages are available. Venue visibility and benefit eligibility depend on the account's organization, membership status and participating partners, rather than the App Store country. France is excluded from distribution at the owner's request.

## Required submission evidence

Both physical-device walkthroughs are attached in App Review Information and finished processing (COMPLETE): `QMETplus_member_physical_iPhone_build22.mp4` and `QMETplus_partner_physical_iPhone_build22.mp4`. They capture the real iPhone display through iPhone Mirroring, begin before launch, and show the existing-session main flows. PIN entry, the private system location preview and idle pauses are omitted. First-login instructions remain above; reviewers should use the supplied credentials and create their own local PIN. No simulated app screens are used. Both versions were resubmitted on 21 November 2026 at 13:16 Asia/Almaty and are waiting for review.

The owner instructed us to explain that QAZAQMETAL is the client commissioning the apps, access/use of its branding and supplied materials is authorized, and all necessary supporting documents can be provided upon request. This statement is saved in both apps' review notes. No signed authorization document has been supplied or represented as attached.
