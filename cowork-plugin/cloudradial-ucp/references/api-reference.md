# CloudRadial API V2 — Quick Reference

Base URL: https://api.us.cloudradial.com
Auth: HTTP Basic (public key = username, private key = password)
OpenAPI: 3.0.1

## Schemas

### ArchiveItem
- `companyReportItemId`: integer [int32]
- `companyReportFolderId`: integer [int32]
- `companyId`: integer [int32]
- `subject`: string (nullable)
- `text`: string (nullable)
- `isHTML`: boolean
- `isError`: boolean
- `dateUploaded`: string [date-time]
- `length`: integer [int64]
- `isDeleted`: boolean
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `attachments`: string (nullable)
- `company`: Company

### ArchiveItemAttachmentResponse
- `attachmentId`: integer [int32]
- `fileName`: string (nullable)
- `contentType`: string (nullable)
- `length`: integer [int64]
- `downloadLink`: string (nullable)

### ArchiveItemRequest
- `companyId`: integer [int32] **REQUIRED** — Tenant company ID
- `archiveId`: integer [int32] **REQUIRED** — Parent archive (folder) ID
- `subject`: string (max 255) **REQUIRED** — Item subject / filename
- `text`: string (nullable) — Optional body text / contents
- `isHtml`: boolean — Whether the CloudRadial.API.Models.Requests.ArchiveItemRequest.Text contains HTML
- `isError`: boolean — Mark item as error

### ArchiveItemResponse
- `archiveItemId`: integer [int32]
- `companyId`: integer [int32]
- `archiveId`: integer [int32]
- `subject`: string (nullable)
- `text`: string (nullable)
- `isHtml`: boolean
- `isError`: boolean
- `dateUploaded`: string [date-time]
- `length`: integer [int64]
- `attachments`: array (nullable)

### Article
- `articleId`: integer [int32]
- `companyId`: integer [int32]
- `subject`: string (nullable)
- `category`: string (nullable)
- `datePublished`: string [date-time]
- `dateCreated`: string [date-time]
- `body`: string (nullable)
- `author`: string (nullable)
- `isFavorite`: boolean
- `isFrontPage`: boolean
- `viewToken`: string [uuid]
- `url`: string (nullable)
- `company`: Company

### ArticleRequest
- `companyId`: integer [int32] **REQUIRED** — Company ID for tenant isolation
- `subject`: string (max 500) **REQUIRED** — Article subject/title
- `category`: string (nullable) (max 200) — Article category
- `datePublished`: string [date-time] **REQUIRED** — Publication date
- `body`: string **REQUIRED** — Article body content
- `author`: string (nullable) (max 200) — Article author
- `isFavorite`: boolean — Whether article is pinned to top of category
- `isFrontPage`: boolean — Whether article is pinned on front page
- `url`: string (nullable) (max 1000) — External URL if article links to external content

### ArticleResponse
- `articleId`: integer [int32] — Article ID
- `companyId`: integer [int32] — Company ID
- `subject`: string (nullable) — Article subject/title
- `category`: string (nullable) — Article category
- `datePublished`: string [date-time] — Publication date
- `body`: string (nullable) — Article body content
- `author`: string (nullable) — Article author
- `isFavorite`: boolean — Whether article is pinned to top of category
- `isFrontPage`: boolean — Whether article is pinned on front page
- `viewToken`: string [uuid] — View token for article access
- `url`: string (nullable) — External URL if article links to external content
- `updateKey`: string [uuid] — Update key for article synchronization
- `dateCreated`: string [date-time] — Date the article was created
- `dateModified`: string [date-time] — Date the article was last modified
- `isSubscribed`: boolean — Whether the article is subscribed
- `isPartnerManaged`: boolean (nullable) — Whether the article is partner managed

### Assessment
- `assessmentId`: integer [int32]
- `companyId`: integer [int32]
- `company`: Company
- `title`: string (nullable)
- `category`: string (nullable)
- `description`: string (nullable)
- `recommendations`: string (nullable)
- `tier`: integer [int32]
- `scheduleInterval`: integer [int32]
- `type`: integer [int32]
- `status`: integer [int32]
- `visibility`: integer [int32]
- `isArchived`: boolean
- `updateKey`: string [uuid]
- `dateConducted`: string [date-time] (nullable)
- `dateNextDue`: string [date-time] (nullable)
- `compliantScore`: integer [int32] (nullable)
- `partialScore`: integer [int32] (nullable)
- `totalScore`: integer [int32] (nullable)
- `maxScore`: integer [int32] (nullable)
- `owner`: string (nullable)
- `ownerApplicationUserId`: string (nullable)
- `psaOpportunityKey`: integer [int64] (nullable)
- `psaProjectKey`: integer [int64] (nullable)
- `psaSalesOrderKey`: integer [int64] (nullable)
- `psaTicketKey`: integer [int64] (nullable)
- `productId`: integer [int32] (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean

### AssessmentImportTemplateRequest
- `assessmentId`: integer [int32] **REQUIRED** — The destination assessment ID to import questions into.
- `templateId`: integer [int32] **REQUIRED** — The source template assessment ID to copy questions from.
- `applyTo`: string (nullable) — Optional scope to apply template to: "server", "endpoint", "user" or anything else for a single copy.

### Catalog
- `companyCatalogId`: integer [int32]
- `companyId`: integer [int32]
- `catalogUsage`: CatalogType
- `category`: string (nullable)
- `description`: string (nullable)
- `subject`: string (nullable)
- `shortDescription`: string (nullable)
- `thankYou`: string (nullable)
- `icon`: string (nullable)
- `iconColor`: string (nullable)
- `iconUrl`: string (nullable)
- `info`: string (nullable)
- `externalReferenceURL`: string (nullable)
- `isAllowedCompanyChanges`: boolean
- `isFavorite`: boolean
- `isFileUpload`: boolean
- `isNeedsApproval`: boolean
- `isShowPrice`: boolean
- `isShowMonthly`: boolean
- `partnerEmailList`: string (nullable)
- `notifyEmailList`: string (nullable)
- `order`: integer [int32]
- `price`: number [double]
- `psaBoard`: string (nullable)
- `psaItem`: string (nullable)
- `psaStatus`: string (nullable)
- `psaSubType`: string (nullable)
- `psaType`: string (nullable)
- `psaPriority`: string (nullable)
- `psaSource`: string (nullable)
- `estimatedTime`: number [double]
- `selectText`: string (nullable)
- `piaFormId`: string (nullable)
- `updateKey`: string [uuid]
- `isPartnerManaged`: boolean (nullable)
- `isSubscribed`: boolean
- `sourcePackageId`: string (nullable)
- `createdBy`: string (nullable)
- `modifiedBy`: string (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean
- `isSignature`: boolean
- `isAppendSubject`: boolean
- `teamsPartnerWebhook`: string (nullable)
- `teamsWebhook`: string (nullable)
- `slackPartnerWebhook`: string (nullable)
- `slackWebhook`: string (nullable)
- `flowPartnerWebhook`: string (nullable)
- `jsonPartnerWebhook`: string (nullable)
- `isSendSubmitter`: boolean
- `psaCategory`: string (nullable)
- `checklist`: string (nullable)
- `script`: string (nullable)
- `approvers`: string (nullable)
- `isIncludeDescription`: boolean
- `isSendToPsa`: boolean
- `isSelfApproval`: boolean
- `hideActionButtons`: boolean
- `groups`: string (nullable)
- `tags`: string (nullable)
- `company`: Company

### CatalogQuestion
- `companyCatalogQuestionId`: integer [int32]
- `companyCatalogId`: integer [int32]
- `companyId`: integer [int32]
- `label`: string (nullable)
- `info`: string (nullable)
- `options`: string (nullable)
- `placeholder`: string (nullable)
- `defaultValue`: string (nullable)
- `order`: integer [int32]
- `type`: CatalogQuestionType
- `isRequired`: boolean
- `isSubject`: boolean
- `isDescription`: boolean
- `jsonId`: string (nullable)
- `isIncludeInTicket`: boolean
- `isUserLookup`: boolean
- `customFieldName`: string (nullable)
- `childQuestionIds`: string (nullable)
- `isDeleted`: boolean

### CatalogQuestionHideConditionResponse
- `questionId`: integer [int32]
- `value`: string (nullable)
- `operator`: string (nullable)

### CatalogQuestionRequest
- `companyCatalogQuestionId`: integer [int32]
- `companyId`: integer [int32] **REQUIRED**
- `companyCatalogId`: integer [int32] **REQUIRED**
- `label`: string (max 500) **REQUIRED**
- `info`: string (nullable)
- `options`: string (nullable)
- `placeholder`: string (nullable)
- `defaultValue`: string (nullable)
- `order`: integer [int32] **REQUIRED**
- `type`: CatalogQuestionType
- `isRequired`: boolean
- `isSubject`: boolean
- `isDescription`: boolean
- `jsonId`: string (nullable)
- `isIncludeInTicket`: boolean
- `isUserLookup`: boolean
- `customFieldName`: string (nullable)
- `hideConditions`: array (nullable)

### CatalogQuestionResponse
- `companyCatalogQuestionId`: integer [int32]
- `companyCatalogId`: integer [int32]
- `companyId`: integer [int32]
- `label`: string (nullable)
- `info`: string (nullable)
- `options`: string (nullable)
- `placeholder`: string (nullable)
- `defaultValue`: string (nullable)
- `order`: integer [int32]
- `type`: CatalogQuestionType
- `isRequired`: boolean
- `isSubject`: boolean
- `isDescription`: boolean
- `jsonId`: string (nullable)
- `isIncludeInTicket`: boolean
- `isUserLookup`: boolean
- `customFieldName`: string (nullable)
- `hideConditions`: array (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]

### CatalogQuestionResponseStandardAPIResponse
- `data`: CatalogQuestionResponse
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### Certificate
- `id`: integer [int32]
- `companyId`: integer [int32]
- `companyDomainId`: integer [int32] (nullable)
- `name`: string (nullable)
- `url`: string (nullable)
- `expirationDate`: string [date-time] (nullable)
- `issuer`: string (nullable)
- `isValid`: boolean (nullable)
- `publicKeyLength`: integer [int32] (nullable)
- `serialNumber`: string (nullable)
- `signatureAlgorithm`: string (nullable)
- `subject`: string (nullable)
- `thumbprint`: string (nullable)
- `x509Version`: integer [int32] (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time] (nullable)
- `isDeleted`: boolean

### CertificateRequest
- `companyId`: integer [int32] **REQUIRED**
- `companyDomainId`: integer [int32] (nullable)
- `name`: string **REQUIRED**
- `url`: string [uri] **REQUIRED**
- `expirationDate`: string [date-time] (nullable)
- `issuer`: string (nullable)
- `isValid`: boolean (nullable)
- `publicKeyLength`: integer [int32] (nullable)
- `serialNumber`: string (nullable)
- `signatureAlgorithm`: string (nullable)
- `subject`: string (nullable)
- `thumbprint`: string (nullable)
- `x509Version`: integer [int32] (nullable)

### CertificateResponse
- `id`: integer [int32]
- `companyId`: integer [int32]
- `companyDomainId`: integer [int32] (nullable)
- `name`: string (nullable)
- `url`: string (nullable)
- `expirationDate`: string [date-time] (nullable)
- `issuer`: string (nullable)
- `isValid`: boolean (nullable)
- `publicKeyLength`: integer [int32] (nullable)
- `serialNumber`: string (nullable)
- `signatureAlgorithm`: string (nullable)
- `subject`: string (nullable)
- `thumbprint`: string (nullable)
- `x509Version`: integer [int32] (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time] (nullable)
- `isDeleted`: boolean

### CertificateResponseStandardAPIResponse
- `data`: CertificateResponse
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### Company
- `companyId`: integer [int32]
- `name`: string (nullable)
- `agentFileName`: string (nullable)
- `dataAgentUrl`: string (nullable)
- `psaIdentifier`: string (nullable)
- `psaKey`: integer [int64]
- `endpointCount`: integer [int32]
- `articles`: array (nullable)
- `endpoints`: array (nullable)

### CompanyCatalogGroupRequest
- `groupName`: string (max 255) **REQUIRED**

### CompanyCatalogGroupResponse
- `groupName`: string (nullable)

### CompanyCatalogQuestionHideConditionRequest
- `questionId`: integer [int32]
- `value`: string (nullable)
- `operator`: string (nullable)

### CompanyCatalogQuestionHideConditionResponse
- `questionId`: integer [int32]
- `value`: string (nullable)
- `operator`: string (nullable)

### CompanyCatalogQuestionRequest
- `companyCatalogQuestionId`: integer [int32]
- `label`: string (max 500) **REQUIRED**
- `info`: string (nullable)
- `options`: string (nullable)
- `placeholder`: string (nullable)
- `type`: CatalogQuestionType
- `isRequired`: boolean
- `isSubject`: boolean
- `isDescription`: boolean
- `order`: integer [int32]
- `defaultValue`: string (nullable)
- `jsonId`: string (nullable)
- `isIncludeInTicket`: boolean
- `isUserLookup`: boolean
- `customFieldName`: string (nullable)
- `hideConditions`: array (nullable)

### CompanyCatalogQuestionResponse
- `companyCatalogQuestionId`: integer [int32]
- `label`: string (nullable)
- `info`: string (nullable)
- `options`: string (nullable)
- `placeholder`: string (nullable)
- `type`: CatalogQuestionType
- `isRequired`: boolean
- `isSubject`: boolean
- `isDescription`: boolean
- `order`: integer [int32]
- `defaultValue`: string (nullable)
- `jsonId`: string (nullable)
- `isIncludeInTicket`: boolean
- `isUserLookup`: boolean
- `customFieldName`: string (nullable)
- `hideConditions`: array (nullable)

### CompanyCatalogRequest
- `companyCatalogId`: integer [int32]
- `companyId`: integer [int32] **REQUIRED**
- `catalogUsage`: CatalogType
- `category`: string (max 255) **REQUIRED**
- `description`: string (nullable)
- `subject`: string (max 255) **REQUIRED**
- `shortDescription`: string (nullable)
- `thankYou`: string (nullable)
- `icon`: string (nullable)
- `iconColor`: string (nullable)
- `iconUrl`: string (nullable)
- `info`: string (nullable)
- `externalReferenceURL`: string (nullable)
- `isAllowedCompanyChanges`: boolean
- `isFavorite`: boolean
- `isFileUpload`: boolean
- `isNeedsApproval`: boolean
- `isShowPrice`: boolean
- `isShowMonthly`: boolean
- `partnerEmailList`: string (nullable)
- `notifyEmailList`: string (nullable)
- `order`: integer [int32]
- `price`: number [double]
- `psaBoard`: string (nullable)
- `psaItem`: string (nullable)
- `psaStatus`: string (nullable)
- `psaSubType`: string (nullable)
- `psaType`: string (nullable)
- `psaPriority`: string (nullable)
- `psaSource`: string (nullable)
- `estimatedTime`: number [double]
- `selectText`: string (nullable)
- `piaFormId`: string (nullable)
- `isPartnerManaged`: boolean (nullable)
- `isSignature`: boolean
- `isAppendSubject`: boolean
- `teamsPartnerWebhook`: string (nullable)
- `teamsWebhook`: string (nullable)
- `slackPartnerWebhook`: string (nullable)
- `slackWebhook`: string (nullable)
- `flowPartnerWebhook`: string (nullable)
- `jsonPartnerWebhook`: string (nullable)
- `isSendSubmitter`: boolean
- `psaCategory`: string (nullable)
- `checklist`: string (nullable)
- `script`: string (nullable)
- `approvers`: string (nullable)
- `isIncludeDescription`: boolean
- `isSendToPsa`: boolean
- `isSelfApproval`: boolean
- `hideActionButtons`: boolean
- `groups`: array (nullable)
- `tags`: array (nullable)
- `questions`: array (nullable)

### CompanyCatalogResponse
- `companyCatalogId`: integer [int32]
- `companyId`: integer [int32]
- `catalogUsage`: CatalogType
- `category`: string (nullable)
- `description`: string (nullable)
- `subject`: string (nullable)
- `shortDescription`: string (nullable)
- `thankYou`: string (nullable)
- `icon`: string (nullable)
- `iconColor`: string (nullable)
- `iconUrl`: string (nullable)
- `info`: string (nullable)
- `externalReferenceURL`: string (nullable)
- `isAllowedCompanyChanges`: boolean
- `isFavorite`: boolean
- `isFileUpload`: boolean
- `isNeedsApproval`: boolean
- `isShowPrice`: boolean
- `isShowMonthly`: boolean
- `partnerEmailList`: string (nullable)
- `notifyEmailList`: string (nullable)
- `order`: integer [int32]
- `price`: number [double]
- `psaBoard`: string (nullable)
- `psaItem`: string (nullable)
- `psaStatus`: string (nullable)
- `psaSubType`: string (nullable)
- `psaType`: string (nullable)
- `psaPriority`: string (nullable)
- `psaSource`: string (nullable)
- `estimatedTime`: number [double]
- `selectText`: string (nullable)
- `piaFormId`: string (nullable)
- `updateKey`: string [uuid]
- `isPartnerManaged`: boolean (nullable)
- `isSubscribed`: boolean
- `createdBy`: string (nullable)
- `modifiedBy`: string (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean
- `isSignature`: boolean
- `isAppendSubject`: boolean
- `teamsPartnerWebhook`: string (nullable)
- `teamsWebhook`: string (nullable)
- `slackPartnerWebhook`: string (nullable)
- `slackWebhook`: string (nullable)
- `flowPartnerWebhook`: string (nullable)
- `jsonPartnerWebhook`: string (nullable)
- `isSendSubmitter`: boolean
- `psaCategory`: string (nullable)
- `checklist`: string (nullable)
- `script`: string (nullable)
- `approvers`: string (nullable)
- `isIncludeDescription`: boolean
- `isSendToPsa`: boolean
- `isSelfApproval`: boolean
- `hideActionButtons`: boolean
- `groups`: array (nullable)
- `tags`: array (nullable)
- `questions`: array (nullable)
- `canBeEdited`: boolean
- `canBeDeleted`: boolean
- `templatePackId`: integer [int32] (nullable)
- `templatePackName`: string (nullable)
- `templatePackLastPublishDate`: string (nullable)

### CompanyCatalogResponseStandardAPIResponse
- `data`: CompanyCatalogResponse
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### CompanyCatalogTagRequest
- `tag`: string (max 255) **REQUIRED**

### CompanyCatalogTagResponse
- `tag`: string (nullable)

### CompanyDomain
- `companyDomainId`: integer [int32] **REQUIRED**
- `companyId`: integer [int32] **REQUIRED**
- `name`: string (max 255) **REQUIRED**
- `description`: string (nullable) (max 500)
- `registrar`: string (nullable) (max 255)
- `hostingCompany`: string (nullable) (max 255)
- `contactName`: string (nullable) (max 255)
- `contactEmail`: string [email] (nullable) (max 255)
- `contactPhone`: string [tel] (nullable) (max 50)
- `dateExpires`: string [date-time] **REQUIRED**
- `isVerified`: boolean **REQUIRED**
- `isOffice365`: boolean **REQUIRED**
- `isDefault`: boolean **REQUIRED**
- `source`: DataSource **REQUIRED**
- `dateCreated`: string [date-time] **REQUIRED**
- `dateModified`: string [date-time] **REQUIRED**
- `isDeleted`: boolean **REQUIRED**
- `company`: Company

### CompanyDomainRequest
- `companyId`: integer [int32] **REQUIRED**
- `name`: string (max 255) **REQUIRED**
- `description`: string (nullable) (max 500)
- `registrar`: string (nullable) (max 255)
- `hostingCompany`: string (nullable) (max 255)
- `contactName`: string (nullable) (max 255)
- `contactEmail`: string [email] (nullable) (max 255)
- `contactPhone`: string [tel] (nullable) (max 50)
- `dateExpires`: string [date-time]
- `isVerified`: boolean
- `isOffice365`: boolean
- `isDefault`: boolean
- `source`: DataSource

### CompanyDomainResponse
- `companyDomainId`: integer [int32]
- `companyId`: integer [int32]
- `name`: string (nullable)
- `description`: string (nullable)
- `registrar`: string (nullable)
- `hostingCompany`: string (nullable)
- `contactName`: string (nullable)
- `contactEmail`: string (nullable)
- `contactPhone`: string (nullable)
- `dateExpires`: string [date-time]
- `isVerified`: boolean
- `isOffice365`: boolean
- `isDefault`: boolean
- `source`: DataSource
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean

### CompanyDomainResponseStandardAPIResponse
- `data`: CompanyDomainResponse
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### CompanyGroup
- `companyGroupId`: integer [int32]
- `group`: string **REQUIRED**
- `partnerId`: integer [int32] **REQUIRED**
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean

### CompanyGroupCompany
- `companyGroupId`: integer [int32]
- `companyId`: integer [int32]
- `partnerId`: integer [int32] **REQUIRED**
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean
- `company`: Company
- `companyGroup`: CompanyGroup

### CompanyGroupCompanyRequest
- `companyGroupId`: integer [int32] **REQUIRED** — Company Group ID
- `companyId`: integer [int32] **REQUIRED** — Company ID

### CompanyGroupCompanyResponse
- `companyGroupId`: integer [int32] — Company Group ID (part of composite key)
- `companyId`: integer [int32] — Company ID (part of composite key)
- `dateCreated`: string [date-time] — Date the group was created
- `dateModified`: string [date-time] — Date the group was last modified

### CompanyGroupRequest
- `group`: string (max 100) **REQUIRED**

### CompanyGroupResponse
- `companyGroupId`: integer [int32] — Company Group ID
- `group`: string (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]

### CompanyRequest
- `name`: string **REQUIRED** — Company name
- `partnerId`: integer [int32] (nullable) — ID of the partner this company belongs to (optional)
- `psaKey`: integer [int64] — PSA Key for the company (optional)
- `psaIdentifier`: string (nullable) — PSA Identifier for the company (optional)
- `territory`: string (nullable) — Territory assigned to the company (optional)
- `accountManager`: string (nullable) — Account manager for the company (optional)

### Course
- `courseId`: integer [int32]
- `companyId`: integer [int32] **REQUIRED**
- `name`: string **REQUIRED**
- `description`: string **REQUIRED**
- `shortDescription`: string **REQUIRED**
- `category`: string **REQUIRED**
- `estimatedTime`: integer [int32] **REQUIRED**
- `isRequired`: boolean **REQUIRED**
- `validMonths`: integer [int32] **REQUIRED**
- `imageName`: string (nullable)
- `isFrontPage`: boolean **REQUIRED**
- `externalCourseId`: string (nullable)
- `isExternalFreeCourse`: boolean
- `passScore`: integer [int32]
- `externalCourseUrl`: string (nullable)
- `courseImageUrl`: string (nullable)
- `enrollmentCount`: integer [int32]
- `completionCount`: integer [int32]
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean
- `company`: Company

### CourseCompletionRequest
- `score`: integer [int32] (nullable) — Optional score achieved in the course (percentage)
- `comment`: string (nullable) — Optional comment or feedback about the course
- `completionDate`: string [date-time] (nullable)

### CourseEnrollment
- `courseEnrollmentId`: integer [int32]
- `courseId`: integer [int32] **REQUIRED**
- `userId`: string (max 450) **REQUIRED**
- `currentLessonId`: integer [int32] **REQUIRED**
- `dateEnrolled`: string [date-time] **REQUIRED**
- `dateCompleted`: string [date-time] (nullable)
- `dateLastAccess`: string [date-time] (nullable)
- `courseName`: string (nullable)
- `courseDescription`: string (nullable)
- `companyId`: integer [int32]
- `isCompleted`: boolean
- `daysSinceEnrollment`: integer [int32]
- `isExpired`: boolean
- `course`: Course

### CourseEnrollmentRequest
- `courseId`: integer [int32] **REQUIRED** — The ID of the course to enroll in
- `userId`: string **REQUIRED** — The ID of the user to enroll in the course

### CourseLesson
- `courseLessonId`: integer [int32]
- `courseId`: integer [int32] **REQUIRED**
- `title`: string **REQUIRED**
- `overview`: string **REQUIRED**
- `category`: string **REQUIRED**
- `text`: string **REQUIRED**
- `order`: integer [int32] **REQUIRED**
- `companyId`: integer [int32]
- `courseName`: string (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean
- `course`: Course

### CourseLessonHistory
- `courseId`: integer [int32]
- `applicationUserId`: string **REQUIRED**
- `courseLessonId`: integer [int32]
- `completedScore`: integer [int32] **REQUIRED**
- `companyId`: integer [int32]
- `courseName`: string (nullable)
- `courseLessonTitle`: string (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean
- `course`: Course
- `courseLesson`: CourseLesson

### CourseLessonHistoryRequest
- `companyId`: integer [int32] **REQUIRED**
- `courseId`: integer [int32] **REQUIRED**
- `applicationUserId`: string (max 450) **REQUIRED**
- `courseLessonId`: integer [int32] **REQUIRED**
- `completedScore`: integer [int32] **REQUIRED**

### CourseLessonHistoryResponse
- `courseLessonHistoryId`: string (nullable) — Course lesson history composite key identifier (for client reference)
Format: {CourseId}-{ApplicationUserId}-{CourseLessonId}
- `courseId`: integer [int32] — Course ID
- `applicationUserId`: string (nullable) — Application User ID
- `courseLessonId`: integer [int32] — Course lesson ID
- `companyId`: integer [int32] — Company ID
- `completedScore`: integer [int32] — Completed score for the lesson
- `dateCreated`: string [date-time] — Date the history record was created
- `dateModified`: string [date-time] — Date the history record was last modified
- `isDeleted`: boolean — Whether the history record is soft deleted

### CourseLessonRequest
- `companyId`: integer [int32] **REQUIRED**
- `courseId`: integer [int32] **REQUIRED**
- `title`: string **REQUIRED**
- `overview`: string **REQUIRED**
- `category`: string **REQUIRED**
- `text`: string **REQUIRED**
- `order`: integer [int32]

### CourseLessonResponse
- `courseLessonId`: integer [int32] — Course lesson ID
- `courseId`: integer [int32] — Course ID
- `companyId`: integer [int32] — Company ID
- `title`: string (nullable) — Lesson title
- `overview`: string (nullable) — Lesson overview
- `category`: string (nullable) — Lesson category
- `text`: string (nullable) — Lesson content text
- `order`: integer [int32] — Lesson order within the course
- `updateKey`: string [uuid] — Update key for lesson synchronization
- `dateCreated`: string [date-time] — Date the lesson was created
- `dateModified`: string [date-time] — Date the lesson was last modified
- `isDeleted`: boolean — Whether the lesson is soft deleted

### CourseRequest
- `name`: string **REQUIRED** — Name of the course
- `description`: string **REQUIRED** — Detailed description of the course
- `shortDescription`: string **REQUIRED** — Short description of the course
- `category`: string **REQUIRED** — Category of the course
- `estimatedTime`: integer [int32] **REQUIRED** — Estimated time to complete the course (in minutes)
- `isRequired`: boolean — Whether the course is required
- `validMonths`: integer [int32] — Number of months before certification expires (0 for never)
- `isFrontPage`: boolean — Whether the course should appear on the front page
- `externalCourseId`: string (nullable) — External course ID if applicable
- `isExternalFreeCourse`: boolean — Whether the external course is free
- `passScore`: integer [int32] — Passing score for the course (percentage)
- `externalCourseUrl`: string (nullable) — URL for external course content if applicable
- `courseImageUrl`: string (nullable) — URL for the course image if applicable
- `companyId`: integer [int32]
- `prerequisites`: array (nullable) — List of prerequisite course IDs
- `groups`: array (nullable) — List of groups to associate with the course

### CreateFlexibleAssetFieldRequest
- `flexibleAssetTypeId`: integer [int32] **REQUIRED**
- `order`: integer [int32]
- `name`: string **REQUIRED**
- `kind`: string **REQUIRED**
- `hint`: string (nullable)
- `defaultValue`: string (nullable)
- `required`: boolean
- `useForTitle`: boolean
- `showInList`: boolean

### CreateFlexibleAssetRequest
- `flexibleAssetTypeId`: integer [int32] **REQUIRED**
- `companyId`: integer [int32] **REQUIRED**
- `resourceUrl`: string (nullable)
- `traits`: object (nullable)

### CreateFlexibleAssetTypeRequest
- `name`: string **REQUIRED**
- `description`: string (nullable)
- `icon`: string (nullable)
- `showInMenu`: boolean
- `fields`: array (nullable)

### Endpoint
- `companyEndpointId`: integer [int32]
- `companyId`: integer [int32] **REQUIRED**
- `name`: string **REQUIRED**
- `lastEmail`: string (nullable)
- `lastSync`: string [date-time] (nullable)
- `os`: string (nullable)
- `edition`: string (nullable)
- `isServer`: boolean
- `processorCount`: integer [int32]
- `systemDirectory`: string (nullable)
- `userDomainName`: string (nullable)
- `userName`: string (nullable)
- `machineName`: string (nullable)
- `serialNumber`: string (nullable)
- `cpu`: string (nullable)
- `is64Bit`: boolean
- `isVirtual`: boolean
- `latitude`: number [double]
- `longitude`: number [double]
- `manufacturer`: string (nullable)
- `model`: string (nullable)
- `dnsAddress`: string (nullable)
- `externalIP`: string (nullable)
- `internalIP`: string (nullable)
- `macAddress`: string (nullable)
- `antiVirus`: string (nullable)
- `osVersion`: string (nullable)
- `workgroup`: string (nullable)
- `siteName`: string (nullable)
- `tagNumber`: string (nullable)
- `psaContactKey`: integer [int32]
- `platformType`: EndpointPlatformType **REQUIRED**
- `isWindowsDefenderRunning`: boolean **REQUIRED**
- `lastOSUpdate`: string [date-time] **REQUIRED**
- `agentVersion`: string (nullable)
- `lastCheckIn`: string [date-time] **REQUIRED**
- `biosDate`: string [date-time] (nullable)
- `enclosure`: EnclosureType **REQUIRED**
- `isOneDrive`: boolean
- `windows11Readiness`: Windows11Status
- `isSSD`: boolean
- `isEncrypted`: boolean
- `cpuDate`: string [date-time] (nullable)
- `expirationDate`: string [date-time] (nullable)
- `contactName`: string (nullable)
- `memory`: integer [int64] (nullable)
- `lastFullCheckIn`: string [date-time] (nullable)
- `manufacturedDate`: string [date-time] (nullable)
- `productNumber`: string (nullable)
- `build`: string (nullable)
- `trayDisplay`: string (nullable)
- `trayEmail`: string (nullable)
- `trayVersion`: string (nullable)
- `isIntune`: boolean (nullable)
- `timeZone`: string (nullable)
- `tpmVersion`: string (nullable)
- `uefiSecureBoot`: boolean (nullable)
- `rmmDeviceId`: string (nullable) (max 100)
- `productKey`: string (nullable)
- `expirationRefreshDate`: string [date-time] (nullable)
- `isBlocked`: boolean (nullable)
- `sid`: string (nullable)
- `screenConnectId`: string (nullable)
- `company`: Company
- `graphicsCards`: array (nullable)
- `userInfo`: array (nullable)
- `auditPolicies`: array (nullable)
- `batteryInfo`: EndpointBatteryInfo
- `defenderStatus`: EndpointDefenderStatus
- `customProperties`: object (nullable)

### EndpointApplication
- `endpointApplicationId`: integer [int32]
- `endpointId`: integer [int32]
- `name`: string (nullable)
- `publisher`: string **REQUIRED**
- `readme`: string (nullable)
- `helpURL`: string (nullable)
- `helpPhone`: string (nullable)
- `aboutURL`: string (nullable)
- `updateURL`: string (nullable)
- `comments`: string (nullable)
- `category`: string (nullable)
- `isCloudStorage`: boolean
- `platformType`: integer [int32]
- `estimatedSize`: integer [int32]
- `installPath`: string (nullable)
- `uninstallPath`: string (nullable)
- `modifyPath`: string (nullable)
- `installDate`: string [date-time] (nullable)
- `display`: string (nullable)
- `major`: integer [int32]
- `minor`: integer [int32]
- `version`: integer [int32]
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `endpoint`: Endpoint
- `companyId`: integer [int32]

### EndpointApplicationRequest
- `companyId`: integer [int32] **REQUIRED** — The company ID for tenant isolation
- `endpointId`: integer [int32] **REQUIRED** — The company endpoint ID
- `name`: string (nullable) — The name of the application
- `publisher`: string **REQUIRED** — The publisher of the application
- `readme`: string (nullable) — The readme information
- `helpURL`: string (nullable) — The help URL
- `helpPhone`: string (nullable) — The help phone number
- `aboutURL`: string (nullable) — The about URL
- `updateURL`: string (nullable) — The update URL
- `comments`: string (nullable) — Comments about the application
- `category`: string (nullable) — The category of the application
- `isCloudStorage`: boolean — Whether the application is cloud storage
- `platformType`: EndpointPlatformType
- `estimatedSize`: integer [int32] — The estimated size of the application
- `installPath`: string (nullable) — The install path of the application
- `uninstallPath`: string (nullable) — The uninstall path of the application
- `modifyPath`: string (nullable) — The modify path of the application
- `installDate`: string [date-time] (nullable) — The install date of the application
- `display`: string (nullable) — The display version of the application
- `major`: integer [int32] — The major version number
- `minor`: integer [int32] — The minor version number
- `version`: integer [int32] — The version number

### EndpointApplicationResponse
- `endpointApplicationId`: integer [int32] — The unique identifier for the endpoint application
- `dateCreated`: string [date-time] — The date the endpoint application was created
- `dateModified`: string [date-time] — The date the endpoint application was last modified
- `companyId`: integer [int32] **REQUIRED** — The company ID for tenant isolation
- `endpointId`: integer [int32] **REQUIRED** — The company endpoint ID
- `name`: string (nullable) — The name of the application
- `publisher`: string **REQUIRED** — The publisher of the application
- `readme`: string (nullable) — The readme information
- `helpURL`: string (nullable) — The help URL
- `helpPhone`: string (nullable) — The help phone number
- `aboutURL`: string (nullable) — The about URL
- `updateURL`: string (nullable) — The update URL
- `comments`: string (nullable) — Comments about the application
- `category`: string (nullable) — The category of the application
- `isCloudStorage`: boolean — Whether the application is cloud storage
- `platformType`: EndpointPlatformType
- `estimatedSize`: integer [int32] — The estimated size of the application
- `installPath`: string (nullable) — The install path of the application
- `uninstallPath`: string (nullable) — The uninstall path of the application
- `modifyPath`: string (nullable) — The modify path of the application
- `installDate`: string [date-time] (nullable) — The install date of the application
- `display`: string (nullable) — The display version of the application
- `major`: integer [int32] — The major version number
- `minor`: integer [int32] — The minor version number
- `version`: integer [int32] — The version number

### EndpointAuditPolicy
- `endpointAuditPolicyId`: integer [int32] **REQUIRED**
- `companyEndpointId`: integer [int32] **REQUIRED**
- `name`: string (nullable) (max 256)
- `auditPolicySubCategoryName`: string (nullable) (max 256)
- `auditPolicySubCategoryStatus`: string (nullable) (max 256)
- `endpoint`: Endpoint

### EndpointBatteryInfo
- `endpointBatteryInfoId`: integer [int32] **REQUIRED**
- `companyEndpointId`: integer [int32] **REQUIRED**
- `name`: string (nullable) (max 1024)
- `description`: string (nullable) (max 1024)
- `status`: string (nullable) (max 1024)
- `errorDescription`: string (nullable) (max 1024)
- `caption`: string (nullable) (max 1024)
- `endpoint`: Endpoint

### EndpointCustomProperty
- `endpointCustomPropertyId`: integer [int32]
- `companyEndpointId`: integer [int32]
- `ownerId`: string (nullable)
- `name`: string (nullable)
- `value`: string (nullable)
- `dataType`: string (nullable)
- `endpoint`: Endpoint
- `serialNumber`: string (nullable)
- `machineName`: string (nullable)
- `manufacturer`: string (nullable)

### EndpointCustomPropertyMutationDto
- `name`: string (nullable)
- `value`: string (nullable)
- `dataType`: string (nullable)

### EndpointDefenderStatus
- `endpointDefenderStatusId`: integer [int32] **REQUIRED**
- `companyEndpointId`: integer [int32] **REQUIRED**
- `engineVersion`: string (nullable) (max 256)
- `productVersion`: string (nullable) (max 256)
- `runningMode`: string (nullable) (max 256)
- `serviceEnabled`: boolean
- `serviceVersion`: string (nullable) (max 256)
- `antispywareEnabled`: boolean
- `antispywareSignatureAge`: integer [int32]
- `antispywareSignatureLastUpdated`: string [date-time] (nullable)
- `antispywareSignatureVersion`: string (nullable) (max 256)
- `antivirusEnabled`: boolean
- `antivirusSignatureAge`: integer [int32]
- `antivirusSignatureLastUpdated`: string [date-time] (nullable)
- `antivirusSignatureVersion`: string (nullable) (max 256)
- `behaviorMonitorEnabled`: boolean
- `computerId`: string (nullable) (max 256)
- `computerState`: integer [int32]
- `fullScanAge`: integer [int32]
- `fullScanStartTime`: string [date-time] (nullable)
- `fullScanEndTime`: string [date-time] (nullable)
- `iOavProtectionEnabled`: boolean
- `isTamperProtected`: boolean
- `isVirtualMachine`: boolean
- `lastFullScanSource`: integer [int32]
- `lastQuickScanSource`: integer [int32]
- `nisEnabled`: boolean
- `nisSignatureAge`: integer [int32]
- `nisEngineVersion`: string (nullable) (max 256)
- `nisSignatureVersion`: string (nullable) (max 256)
- `nisSignatureLastUpdated`: string [date-time] (nullable)
- `onAccessProtectionEnabled`: boolean
- `quickScanAge`: integer [int32]
- `quickScanStartTime`: string [date-time] (nullable)
- `quickScanEndTime`: string [date-time] (nullable)
- `realTimeProtectionEnabled`: boolean
- `realTimeScanDirection`: integer [int32]
- `endpoint`: Endpoint

### EndpointGraphicsCard
- `endpointGraphicsCardId`: integer [int32] **REQUIRED**
- `companyEndpointId`: integer [int32] **REQUIRED**
- `name`: string (max 1024) **REQUIRED**
- `driverVersion`: string (nullable) (max 1024)
- `adapterRAM`: string (nullable) (max 1024)
- `verticalResolution`: string (nullable) (max 1024)
- `horizontalResolution`: string (nullable) (max 1024)
- `endpoint`: Endpoint

### EndpointUserInfo
- `endpointUserInfoId`: integer [int32] **REQUIRED**
- `companyEndpointId`: integer [int32] **REQUIRED**
- `caption`: string (nullable) (max 1024)
- `description`: string (nullable) (max 1024)
- `domain`: string (nullable) (max 1024)
- `fullName`: string (nullable) (max 1024)
- `samName`: string (nullable) (max 1024)
- `isPasswordRequired`: boolean
- `isPasswordExpires`: boolean
- `isPasswordChangeable`: boolean
- `isDisabled`: boolean
- `isRegistryAvailable`: boolean
- `screenSaveTimeout`: integer [int32]
- `isAzureAD`: boolean
- `isAdministrator`: boolean
- `sid`: string (nullable) (max 1024)
- `endpoint`: Endpoint

### Feedback
- `feedbackId`: integer [int32]
- `partnerId`: integer [int32]
- `userId`: string (nullable)
- `userPsaId`: integer [int64]
- `userEmail`: string (nullable)
- `userFirstName`: string (nullable)
- `userLastName`: string (nullable)
- `companyId`: integer [int32]
- `companyPsaId`: integer [int64]
- `companyName`: string (nullable)
- `ticketPsaId`: integer [int64]
- `ticketDate`: string [date-time] (nullable)
- `ticketSubject`: string (nullable)
- `agentPsaId`: integer [int64]
- `agentFirstName`: string (nullable)
- `agentLastName`: string (nullable)
- `agentEmail`: string (nullable)
- `sentiment`: integer [int32]
- `feedbackRatingNumber`: number [double]
- `feedbackRating`: FeedbackType
- `feedbackComment`: string (nullable)
- `feedbackWantsFollowUp`: boolean
- `feedbackOnWebsite`: boolean
- `feedbackReferralClick`: boolean
- `feedbackIpAddress`: string (nullable)
- `source`: FeedbackSource
- `phone`: string (nullable)
- `ticketString`: string (nullable)
- `userAgent`: string (nullable)
- `agentImageUrl`: string (nullable)
- `isValidated`: boolean
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean

### FeedbackRequest
- `companyId`: integer [int32] **REQUIRED**
- `userId`: string (nullable)
- `userPsaId`: integer [int64]
- `userFirstName`: string (nullable)
- `userLastName`: string (nullable)
- `userEmail`: string (nullable)
- `companyPsaId`: integer [int64]
- `companyName`: string (nullable)
- `ticketPsaId`: integer [int64]
- `ticketDate`: string [date-time] (nullable)
- `ticketSubject`: string (nullable)
- `agentPsaId`: integer [int64]
- `agentFirstName`: string (nullable)
- `agentLastName`: string (nullable)
- `agentEmail`: string (nullable)
- `sentiment`: integer [int32] **REQUIRED**
- `feedbackRatingNumber`: number [double]
- `feedbackRating`: FeedbackType
- `feedbackComment`: string (nullable)
- `feedbackWantsFollowUp`: boolean
- `feedbackOnWebsite`: boolean
- `feedbackReferralClick`: boolean
- `feedbackIpAddress`: string (nullable)
- `source`: FeedbackSource
- `phone`: string (nullable)
- `ticketString`: string (nullable)
- `userAgent`: string (nullable)
- `agentImageUrl`: string (nullable)
- `isValidated`: boolean
- `isDeleted`: boolean

### FeedbackResponse
- `id`: integer [int32]
- `partnerId`: integer [int32]
- `companyId`: integer [int32]
- `userId`: string (nullable)
- `userPsaId`: integer [int64]
- `userFirstName`: string (nullable)
- `userLastName`: string (nullable)
- `userEmail`: string (nullable)
- `companyPsaId`: integer [int64]
- `companyName`: string (nullable)
- `ticketPsaId`: integer [int64]
- `ticketDate`: string [date-time] (nullable)
- `ticketSubject`: string (nullable)
- `agentPsaId`: integer [int64]
- `agentFirstName`: string (nullable)
- `agentLastName`: string (nullable)
- `agentEmail`: string (nullable)
- `sentiment`: integer [int32]
- `feedbackRatingNumber`: number [double]
- `feedbackRating`: FeedbackType
- `feedbackComment`: string (nullable)
- `feedbackWantsFollowUp`: boolean
- `feedbackOnWebsite`: boolean
- `feedbackReferralClick`: boolean
- `feedbackIpAddress`: string (nullable)
- `source`: FeedbackSource
- `phone`: string (nullable)
- `ticketString`: string (nullable)
- `userAgent`: string (nullable)
- `agentImageUrl`: string (nullable)
- `isValidated`: boolean
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time] (nullable)
- `isDeleted`: boolean

### FeedbackResponseStandardAPIResponse
- `data`: FeedbackResponse
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### FlexibleAsset
- `id`: integer [int32]
- `flexibleAssetTypeId`: integer [int32] **REQUIRED**
- `companyId`: integer [int32] **REQUIRED**
- `name`: string (nullable) (max 256)
- `resourceUrl`: string (nullable) (max 1024)
- `traitsJson`: string (nullable)
- `type`: FlexibleAssetType

### FlexibleAssetAttributesBulkDeleteDto
- `id`: integer [int32] **REQUIRED**

### FlexibleAssetAttributesBulkUpdateDto
- `id`: integer [int32] **REQUIRED**
- `flexible-asset-type-id`: integer [int32] (nullable)
- `archived`: boolean (nullable)
- `traits`: object (nullable)
- `organization-id`: integer [int32] (nullable)

### FlexibleAssetAttributesCreateDto
- `organization-id`: integer [int32] (nullable)
- `flexible-asset-type-id`: integer [int32] **REQUIRED**
- `archived`: boolean
- `traits`: object **REQUIRED**

### FlexibleAssetAttributesUpdateDto
- `flexible-asset-type-id`: integer [int32] (nullable)
- `archived`: boolean (nullable)
- `traits`: object (nullable)
- `organization-id`: integer [int32] (nullable)

### FlexibleAssetBulkDeleteDto
- `attributes`: FlexibleAssetAttributesBulkDeleteDto **REQUIRED**
- `type`: string **REQUIRED**

### FlexibleAssetBulkDeleteRequestDto
- `data`: array **REQUIRED**

### FlexibleAssetBulkUpdateDto
- `attributes`: FlexibleAssetAttributesBulkUpdateDto
- `type`: string **REQUIRED**

### FlexibleAssetBulkUpdateDtoListFlexibleAssetRequestDto
- `data`: array **REQUIRED**

### FlexibleAssetCreateDto
- `attributes`: FlexibleAssetAttributesCreateDto **REQUIRED**
- `type`: string **REQUIRED**

### FlexibleAssetCreateDtoFlexibleAssetRequestDto
- `data`: FlexibleAssetCreateDto **REQUIRED**

### FlexibleAssetCreateDtoListFlexibleAssetRequestDto
- `data`: array **REQUIRED**

### FlexibleAssetField
- `id`: integer [int32]
- `flexibleAssetTypeId`: integer [int32] **REQUIRED**
- `order`: integer [int32]
- `name`: string (max 256) **REQUIRED**
- `nameKey`: string (max 256) **REQUIRED**
- `kind`: string (max 30) **REQUIRED**
- `hint`: string (nullable)
- `decimals`: integer [int32] (nullable)
- `defaultValue`: string (nullable)
- `tagType`: string (nullable)
- `required`: boolean
- `useForTitle`: boolean
- `expiration`: boolean (nullable)
- `showInList`: boolean
- `type`: FlexibleAssetType

### FlexibleAssetFieldAttributesCreateDto
- `name`: string **REQUIRED**
- `order`: integer [int32] **REQUIRED**
- `kind`: string **REQUIRED**
- `required`: boolean
- `hint`: string (nullable)
- `default-value`: string (nullable)
- `tag-type`: string (nullable)
- `decimals`: integer [int32] (nullable)
- `expiration`: boolean (nullable)
- `use-for-title`: boolean
- `show-in-list`: boolean

### FlexibleAssetFieldCreateDto
- `attributes`: FlexibleAssetFieldAttributesCreateDto **REQUIRED**
- `type`: string **REQUIRED**

### FlexibleAssetFieldCreateDtoFlexibleAssetRequestDto
- `data`: FlexibleAssetFieldCreateDto **REQUIRED**

### FlexibleAssetType
- `id`: integer [int32]
- `name`: string (max 256) **REQUIRED**
- `description`: string (nullable) (max 1024)
- `icon`: string (nullable) (max 50)
- `showInMenu`: boolean
- `fields`: array (nullable)
- `flexibleAssets`: array (nullable)

### FlexibleAssetTypeAttributesCreateDto
- `name`: string **REQUIRED**
- `description`: string (nullable)
- `icon`: string (nullable)
- `show-in-menu`: boolean

### FlexibleAssetTypeAttributesUpdateDto
- `fields`: array (nullable)
- `name`: string **REQUIRED**
- `description`: string (nullable)
- `icon`: string (nullable)
- `show-in-menu`: boolean

### FlexibleAssetTypeCreateDto
- `attributes`: FlexibleAssetTypeAttributesCreateDto **REQUIRED**
- `relationships`: FlexibleAssetTypeRelationshipsCreateDto
- `type`: string **REQUIRED**

### FlexibleAssetTypeCreateDtoFlexibleAssetRequestDto
- `data`: FlexibleAssetTypeCreateDto **REQUIRED**

### FlexibleAssetTypeRelationshipDataCreateDto
- `data`: array **REQUIRED**

### FlexibleAssetTypeRelationshipsCreateDto
- `flexible-asset-fields`: FlexibleAssetTypeRelationshipDataCreateDto

### FlexibleAssetTypeUpdateDto
- `id`: integer [int32]
- `attributes`: FlexibleAssetTypeAttributesUpdateDto
- `type`: string **REQUIRED**

### FlexibleAssetTypeUpdateDtoFlexibleAssetRequestDto
- `data`: FlexibleAssetTypeUpdateDto **REQUIRED**

### FlexibleAssetUpdateDto
- `id`: integer [int32] **REQUIRED**
- `attributes`: FlexibleAssetAttributesUpdateDto
- `type`: string **REQUIRED**

### FlexibleAssetUpdateDtoFlexibleAssetRequestDto
- `data`: FlexibleAssetUpdateDto **REQUIRED**

### Media
- `partnerMediaId`: integer [int32]
- `partnerId`: integer [int32]
- `description`: string (nullable)
- `originalName`: string (nullable)
- `length`: integer [int64]
- `width`: integer [int32]
- `height`: integer [int32]
- `hash`: string (nullable)
- `contentType`: string (nullable)
- `viewToken`: string [uuid]
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean

### MediaRequest
- `description`: string (nullable)
- `originalName`: string **REQUIRED**
- `data`: string [byte] **REQUIRED**
- `length`: integer [int64] **REQUIRED**
- `width`: integer [int32] **REQUIRED**
- `height`: integer [int32] **REQUIRED**
- `hash`: string (nullable) (max 32)
- `contentType`: string (nullable) (max 100)

### MediaResponse
- `partnerMediaId`: integer [int32]
- `partnerId`: integer [int32]
- `description`: string (nullable)
- `originalName`: string (nullable)
- `length`: integer [int64]
- `width`: integer [int32]
- `height`: integer [int32]
- `hash`: string (nullable)
- `contentType`: string (nullable)
- `viewToken`: string [uuid]
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean

### MediaResponseStandardAPIResponse
- `data`: MediaResponse
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### Menu
- `companyMenuId`: integer [int32]
- `companyId`: integer [int32]
- `applicationUserId`: string (nullable)
- `editRights`: integer [int32]
- `name`: string **REQUIRED**
- `url`: string **REQUIRED**
- `category`: string **REQUIRED**
- `color`: string (nullable)
- `icon`: string (nullable)
- `iconColor`: string (nullable)
- `iconUrl`: string (nullable)
- `instructions`: string (nullable)
- `order`: integer [int32]
- `source`: DataSource
- `toolTip`: string (nullable)
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean
- `updateKey`: string [uuid]
- `isSubscribed`: boolean
- `isPartnerManaged`: boolean (nullable)
- `groups`: string (nullable)
- `tags`: string (nullable)

### MenuRequest
- `companyId`: integer [int32] **REQUIRED** — Company ID for tenant isolation
- `applicationUserId`: string (nullable) — Application User ID (optional for personal menu items)
- `editRights`: integer [int32] **REQUIRED** — Edit rights level
- `name`: string (max 500) **REQUIRED** — Menu item name
- `url`: string (max 2000) **REQUIRED** — Menu item URL
- `category`: string (max 200) **REQUIRED** — Menu category
- `color`: string (nullable) (max 50) — Menu item color
- `icon`: string (nullable) (max 100) — Menu item icon
- `iconColor`: string (nullable) (max 50) — Menu item icon color
- `iconUrl`: string (nullable) (max 2000) — Menu item icon URL
- `instructions`: string (nullable) — Menu item instructions
- `order`: integer [int32] **REQUIRED** — Menu item display order
- `source`: DataSource
- `toolTip`: string (nullable) (max 500) — Menu item tooltip
- `groups`: array (nullable) — List of group names associated with this menu item

### MenuResponse
- `companyMenuId`: integer [int32] — Menu ID
- `companyId`: integer [int32] — Company ID
- `applicationUserId`: string (nullable) — Application User ID (for personal menu items)
- `editRights`: integer [int32] — Edit rights level
- `name`: string (nullable) — Menu item name
- `url`: string (nullable) — Menu item URL
- `category`: string (nullable) — Menu category
- `color`: string (nullable) — Menu item color
- `icon`: string (nullable) — Menu item icon
- `iconColor`: string (nullable) — Menu item icon color
- `iconUrl`: string (nullable) — Menu item icon URL
- `instructions`: string (nullable) — Menu item instructions
- `order`: integer [int32] — Menu item display order
- `source`: DataSource
- `toolTip`: string (nullable) — Menu item tooltip
- `dateCreated`: string [date-time] — Date created
- `dateModified`: string [date-time] — Date modified
- `isDeleted`: boolean — Whether the item is deleted
- `updateKey`: string [uuid] — Update key for optimistic concurrency
- `isSubscribed`: boolean — Whether the item is subscribed
- `isPartnerManaged`: boolean (nullable) — Whether the item is partner managed
- `createdBy`: string (nullable) — Created by user
- `modifiedBy`: string (nullable) — Modified by user
- `groups`: array (nullable) — List of group names associated with this menu item

### Operation
- `value`: object (nullable)
- `path`: string (nullable)
- `op`: string (nullable)
- `from`: string (nullable)

### Product
- `productId`: integer [int32]
- `companyId`: integer [int32]
- `productCategoryId`: integer [int32]
- `productCode`: string (nullable)
- `subject`: string **REQUIRED**
- `category`: string **REQUIRED**
- `datePublished`: string [date-time]
- `body`: string **REQUIRED**
- `summary`: string (nullable)
- `isFavorite`: boolean
- `isFrontPage`: boolean
- `viewToken`: string [uuid]
- `url`: string (nullable)
- `assigned`: string (nullable)
- `isActive`: boolean
- `isClientVisible`: boolean
- `scoring`: integer [int32]
- `isRequired`: boolean
- `isShowClientLabel`: boolean
- `clientLabel`: string (nullable)
- `isShowPrice`: boolean
- `isShowEstimated`: boolean
- `monthlyUnits`: number [double]
- `monthlyUnitPrice`: number [double]
- `monthlyUnitCost`: number [double]
- `projectUnits`: number [double]
- `projectUnitPrice`: number [double]
- `projectUnitCost`: number [double]
- `estimatedTotalHours`: integer [int32]
- `estimatedDaysDuration`: integer [int32]
- `estimatedStaff`: integer [int32]
- `currentlyInstalled`: boolean
- `priority`: MatrixPriority
- `status`: MatrixStatus
- `statusComplete`: integer [int32]
- `installDate`: string [date-time] (nullable)
- `suggestedBy`: string (nullable)
- `reminderDate`: string [date-time] (nullable)
- `notes`: string (nullable)
- `scheduledQuarter`: integer [int32]
- `order`: integer [int32]
- `source`: string (nullable)
- `psaTicketKey`: integer [int64]
- `psaProjectKey`: integer [int64]
- `psaOpportunityKey`: integer [int64]
- `psaSalesOrderKey`: integer [int64]
- `assessmentKey`: integer [int32]
- `assessmentQuestionKey`: integer [int32]
- `editRights`: integer [int32]
- `estimatedStartDate`: string [date-time] (nullable)
- `estimatedEndDate`: string [date-time] (nullable)
- `productType`: integer [int32]
- `quarterOffset`: integer [int32]
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean
- `company`: Company

### ProductCategoryRequest
- `productCategoryId`: integer [int32] (nullable) — Optional: If provided, updates existing category. If null, creates new category.
- `name`: string **REQUIRED** — Required: Category name
- `order`: integer [int32] — Display order for the category
- `color`: string (nullable) — Optional: Category color (hex code)
- `body`: string (nullable) — Optional: Category description/body

### ProductRequest
- `companyId`: integer [int32] **REQUIRED**
- `productCategoryId`: integer [int32] **REQUIRED**
- `productCode`: string (nullable)
- `subject`: string **REQUIRED**
- `category`: string **REQUIRED**
- `datePublished`: string [date-time] **REQUIRED**
- `body`: string **REQUIRED**
- `summary`: string **REQUIRED**
- `isFavorite`: boolean
- `isFrontPage`: boolean
- `url`: string (nullable)
- `assigned`: string (nullable)
- `isActive`: boolean
- `isClientVisible`: boolean
- `scoring`: integer [int32]
- `isRequired`: boolean **REQUIRED**
- `isShowClientLabel`: boolean
- `clientLabel`: string (nullable) (max 1024)
- `isShowPrice`: boolean **REQUIRED**
- `isShowEstimated`: boolean
- `monthlyUnits`: number [double]
- `monthlyUnitPrice`: number [double]
- `monthlyUnitCost`: number [double]
- `projectUnits`: number [double]
- `projectUnitPrice`: number [double]
- `projectUnitCost`: number [double]
- `estimatedTotalHours`: integer [int32]
- `estimatedDaysDuration`: integer [int32]
- `estimatedStaff`: integer [int32]
- `currentlyInstalled`: boolean
- `priority`: MatrixPriority
- `status`: MatrixStatus
- `statusComplete`: integer [int32]
- `installDate`: string [date-time] (nullable)
- `suggestedBy`: string (nullable)
- `reminderDate`: string [date-time] (nullable)
- `notes`: string (nullable)
- `scheduledQuarter`: integer [int32]
- `order`: integer [int32]
- `source`: string (nullable)
- `psaTicketKey`: integer [int64]
- `psaProjectKey`: integer [int64]
- `psaOpportunityKey`: integer [int64]
- `psaSalesOrderKey`: integer [int64]
- `assessmentKey`: integer [int32]
- `assessmentQuestionKey`: integer [int32]
- `editRights`: integer [int32]
- `estimatedStartDate`: string [date-time] (nullable)
- `estimatedEndDate`: string [date-time] (nullable)
- `productType`: integer [int32]
- `quarterOffset`: integer [int32]
- `tags`: array (nullable) — List of tags to associate with the product
- `categoryData`: ProductCategoryRequest

### ProductResponse
- `productId`: integer [int32]
- `companyId`: integer [int32]
- `productCategoryId`: integer [int32]
- `productCode`: string (nullable)
- `subject`: string (nullable)
- `category`: string (nullable)
- `datePublished`: string [date-time]
- `body`: string (nullable)
- `summary`: string (nullable)
- `isFavorite`: boolean
- `isFrontPage`: boolean
- `viewToken`: string [uuid]
- `url`: string (nullable)
- `assigned`: string (nullable)
- `isActive`: boolean
- `isClientVisible`: boolean
- `scoring`: integer [int32]
- `isRequired`: boolean
- `isShowClientLabel`: boolean
- `clientLabel`: string (nullable)
- `isShowPrice`: boolean
- `isShowEstimated`: boolean
- `monthlyUnits`: number [double]
- `monthlyUnitPrice`: number [double]
- `monthlyUnitCost`: number [double]
- `projectUnits`: number [double]
- `projectUnitPrice`: number [double]
- `projectUnitCost`: number [double]
- `estimatedTotalHours`: integer [int32]
- `estimatedDaysDuration`: integer [int32]
- `estimatedStaff`: integer [int32]
- `currentlyInstalled`: boolean
- `priority`: MatrixPriority
- `status`: MatrixStatus
- `statusComplete`: integer [int32]
- `installDate`: string [date-time] (nullable)
- `suggestedBy`: string (nullable)
- `reminderDate`: string [date-time] (nullable)
- `notes`: string (nullable)
- `scheduledQuarter`: integer [int32]
- `order`: integer [int32]
- `source`: string (nullable)
- `psaTicketKey`: integer [int64]
- `psaProjectKey`: integer [int64]
- `psaOpportunityKey`: integer [int64]
- `psaSalesOrderKey`: integer [int64]
- `assessmentKey`: integer [int32]
- `assessmentQuestionKey`: integer [int32]
- `editRights`: integer [int32]
- `estimatedStartDate`: string [date-time] (nullable)
- `estimatedEndDate`: string [date-time] (nullable)
- `productType`: integer [int32]
- `quarterOffset`: integer [int32]
- `tags`: array (nullable) — List of tags associated with the product
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isDeleted`: boolean

### ProductResponseStandardAPIResponse
- `data`: ProductResponse
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### Quickstart
- `quickstartId`: integer [int32]
- `companyId`: integer [int32]
- `subject`: string (nullable)
- `description`: string (nullable)
- `category`: string (nullable)
- `body`: string (nullable)
- `icon`: string (nullable)
- `iconColor`: string (nullable)
- `iconUrl`: string (nullable)
- `datePublished`: string [date-time]
- `dateCreated`: string [date-time]
- `isText`: boolean
- `isFavorite`: boolean
- `editRights`: integer [int32]
- `length`: integer [int64]
- `contentType`: string (nullable)
- `viewToken`: string [uuid]
- `company`: Company

### QuickstartRequest
- `companyId`: integer [int32] **REQUIRED** — Company ID for tenant isolation
- `subject`: string (max 500) **REQUIRED** — Quickstart subject/title
- `description`: string **REQUIRED** — Short description
- `category`: string (max 200) **REQUIRED** — Category
- `body`: string (nullable) — Body content (used when IsText is true)
- `icon`: string **REQUIRED** — Icon name
- `iconColor`: string **REQUIRED** — Icon color
- `iconUrl`: string (nullable) — Icon URL
- `datePublished`: string [date-time] **REQUIRED** — Publication date
- `isText`: boolean **REQUIRED** — Indicates if this quickstart stores text content in Body
- `isFavorite`: boolean — Pinned/favorite flag
- `length`: integer [int64] (nullable) — Total payload length in bytes for non-text content. If IsText, it's derived from Body length.
- `contentType`: string (nullable) (max 100) — MIME content type, required for non-text content

### QuickstartResponse
- `quickstartId`: integer [int32]
- `companyId`: integer [int32]
- `subject`: string (nullable)
- `description`: string (nullable)
- `category`: string (nullable)
- `body`: string (nullable)
- `icon`: string (nullable)
- `iconColor`: string (nullable)
- `iconUrl`: string (nullable)
- `datePublished`: string [date-time]
- `isText`: boolean
- `isFavorite`: boolean
- `length`: integer [int64]
- `contentType`: string (nullable)
- `viewToken`: string [uuid]
- `updateKey`: string [uuid]
- `dateCreated`: string [date-time]
- `dateModified`: string [date-time]
- `isSubscribed`: boolean
- `isPartnerManaged`: boolean (nullable)

### Service
- `serviceId`: integer [int32]
- `companyId`: integer [int32]
- `name`: string (nullable)
- `description`: string (nullable)
- `category`: string (nullable)

### ServiceInstall
- `endpointId`: integer [int32]
- `serviceId`: integer [int32]
- `status`: string (nullable)
- `startupType`: string (nullable)
- `fullVersion`: string (nullable)
- `version`: integer [int32] (nullable)
- `major`: integer [int32] (nullable)
- `minor`: integer [int32] (nullable)
- `endpoint`: Endpoint
- `service`: Service

### ServiceInstallRequest
- `endpointId`: integer [int32] **REQUIRED** — The endpoint ID
- `serviceId`: integer [int32] **REQUIRED** — The service ID
- `status`: string (nullable) (max 100) — The status of the service installation
- `startupType`: string (nullable) (max 100) — The startup type of the service
- `fullVersion`: string (nullable) (max 50) — The full version of the service
- `version`: integer [int32] (nullable) — The version number
- `major`: integer [int32] (nullable) — The major version number
- `minor`: integer [int32] (nullable) — The minor version number

### ServiceInstallResponse
- `endpointId`: integer [int32] — The endpoint ID
- `serviceId`: integer [int32] — The service ID
- `status`: string (nullable) — The status of the service installation
- `startupType`: string (nullable) — The startup type of the service
- `fullVersion`: string (nullable) — The full version of the service
- `version`: integer [int32] (nullable) — The version number
- `major`: integer [int32] (nullable) — The major version number
- `minor`: integer [int32] (nullable) — The minor version number

### ServiceInstallUpdateRequest
- `status`: string (nullable) (max 100) — The status of the service installation
- `startupType`: string (nullable) (max 100) — The startup type of the service
- `fullVersion`: string (nullable) (max 50) — The full version of the service
- `version`: integer [int32] (nullable) — The version number
- `major`: integer [int32] (nullable) — The major version number
- `minor`: integer [int32] (nullable) — The minor version number
- `companyId`: integer [int32] **REQUIRED** — The company ID for tenant scoping
- `endpointId`: integer [int32]
- `serviceId`: integer [int32]

### ServiceRequest
- `companyId`: integer [int32] **REQUIRED** — Company ID that owns this service
- `name`: string (max 100) **REQUIRED** — Name of the service
- `description`: string (nullable) (max 500) — Description of the service
- `category`: string (nullable) (max 100) — Category of the service

### ServiceResponse
- `serviceId`: integer [int32] — Service ID
- `companyId`: integer [int32] — Company ID that owns this service
- `name`: string (nullable) — Name of the service
- `description`: string (nullable) — Description of the service
- `category`: string (nullable) — Category of the service
- `dateCreated`: string [date-time] — Date when the service was created
- `dateModified`: string [date-time] — Date when the service was last modified

### StandardAPIResponse
- `success`: boolean
- `message`: string (nullable)

### Token
- `companyId`: integer [int32]
- `name`: string **REQUIRED**
- `companyName`: string (nullable)
- `partnerId`: integer [int32] **REQUIRED**
- `value`: string (nullable)
- `type`: integer [int32]
- `company`: Company

### TokenRequest
- `companyId`: integer [int32] **REQUIRED** — Company ID (0 for partner-level tokens, >0 for company-level tokens)
- `token`: string (max 255) **REQUIRED** — Token name (case-sensitive)
- `value`: string **REQUIRED** — Token value (empty string allowed for placeholder tokens)
- `type`: VariableType

### TokenResponse
- `companyId`: integer [int32] — Company ID (0 for partner-level tokens, >0 for company-level tokens)
- `token`: string (nullable) — Token name
- `value`: string (nullable) — Token value
- `type`: VariableType

### TokenResponseListStandardAPIResponse
- `data`: array (nullable) — The return data
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### TokenResponseStandardAPIResponse
- `data`: TokenResponse
- `success`: boolean — The status of the API call if not success
- `message`: string (nullable) — Any relevant messages for the consumer

### User
- `userId`: string (nullable)
- `email`: string (nullable)
- `firstName`: string (nullable)
- `lastName`: string (nullable)
- `userName`: string (nullable)
- `phoneNumber`: string (nullable)
- `companyId`: integer [int32]
- `displayName`: string (nullable)
- `department`: string (nullable)
- `title`: string (nullable)
- `country`: string (nullable)
- `streetAddress`: string (nullable)
- `city`: string (nullable)
- `state`: string (nullable)
- `postalCode`: string (nullable)
- `mobilePhone`: string (nullable)
- `isDeleted`: boolean
- `dateCreated`: string [date-time] (nullable)
- `dateModified`: string [date-time] (nullable)
- `psaKey`: integer [int64]
- `psaSiteKey`: integer [int64]
- `psaChildAccountKey`: integer [int64]
- `company`: Company

### UserRequest
- `email`: string [email] **REQUIRED** — User's email address
- `companyId`: integer [int32] **REQUIRED** — The ID of the company this user belongs to.
- `firstName`: string **REQUIRED** — User's first name
- `lastName`: string **REQUIRED** — User's last name
- `userName`: string (nullable) — User's username (optional)
- `phoneNumber`: string (nullable) — User's phone number (optional)
- `mobilePhone`: string (nullable) — User's mobile phone (optional)
- `department`: string (nullable) — User's department (optional)
- `title`: string (nullable) — User's title (optional)
- `country`: string (nullable) — User's country (optional)
- `streetAddress`: string (nullable) — User's street address (optional)
- `city`: string (nullable) — User's city (optional)
- `state`: string (nullable) — User's state (optional)
- `postalCode`: string (nullable) — User's postal code (optional)
- `isShowInDirectory`: boolean — Whether to show the user in directory
- `isPartnerAdminUser`: boolean — Whether the user is a partner admin
- `is365Active`: boolean — Whether the user has an active Microsoft 365 account
- `isCompliance`: boolean — Whether the user is compliant
- `isDigestOptIn`: boolean — Whether the user should receive digest emails (frontend naming)
- `isDirectOptIn`: boolean — Whether the user should receive direct messages
- `isOfficeStrongAuthentication`: boolean — Whether the user has multi-factor authentication enabled
- `psaKey`: integer [int64] — User's PSA Key
- `psaSiteKey`: integer [int64] — User's PSA Site Key
- `psaChildAccountKey`: integer [int64] — User's PSA Child Account Key
- `isLoginDisabled`: boolean — Whether the user login is disabled
- `priorityStatus`: ApplicationUserPriorityType
- `source`: DataSource
- `ticketBoardOverride`: string (nullable) (max 4000) — User's ticket board override
- `ticketStatusOverride`: string (nullable) (max 4000) — User's ticket status override

### UserResponseDto
- `userId`: string (nullable) — The unique identifier for the user
- `applicationUserId`: string (nullable) — The application user identifier (alias for UserId for API consistency)
- `email`: string (nullable) — Email address of the user
- `firstName`: string (nullable) — First name of the user
- `lastName`: string (nullable) — Last name of the user
- `userName`: string (nullable) — Username of the user
- `phoneNumber`: string (nullable) — Phone number of the user
- `companyId`: integer [int32] — Company ID the user belongs to
- `displayName`: string (nullable) — Display name (typically FirstName + LastName)
- `psaKey`: integer [int64] — PSA Key identifier for the user
- `psaSiteKey`: integer [int64] — PSA Site Key identifier for the user
- `psaChildAccountKey`: integer [int64] — PSA Child Account Key identifier for the user

## Enumerations

Integer enum types surfaced by the API. Values are the accepted `int32` codes; the API does not expose symbolic names for them. Fields typed as one of these (e.g. `Catalog.catalogUsage: CatalogType`) accept only these values.

- `ApplicationUserPriorityType`: 0, 10
- `CatalogQuestionType`: 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 130, 140, 150, 160, 170, 180, 190, 200, 210, 220, 230, 999
- `CatalogType`: 0, 10, 99
- `DataSource`: 0, 1, 2, 5, 10, 20, 30, 100
- `EnclosureType`: 0, 10, 20, 30, 40, 50, 60, 70, 80, 90
- `EndpointPlatformType`: 0, 1, 2, 99, -1
- `FeedbackSource`: 0, 1, 2, 3, 4
- `FeedbackType`: 0, 1, -1
- `MatrixPriority`: 0, 1, -1
- `MatrixStatus`: 0, 1, 10, 20, 30, 40, 50, 60
- `VariableType`: 0, 1, 2, 3, 4
- `Windows11Status`: 1, 2, -2, -1

## Endpoints

- **GET** `/compatibility/flexible_asset_types` [FlexibleAssetType]  | Params: filter[id] (query), filter[name] (query), filter[icon] (query), filter[enabled] (query), page[number] (query), page[size] (query), include (query), sort (query)
- **POST** `/compatibility/flexible_asset_types` [FlexibleAssetType] 
- **GET** `/compatibility/flexible_asset_types/{id}` [FlexibleAssetType]  | Params: id (path), include (query)
- **PATCH** `/compatibility/flexible_asset_types/{id}` [FlexibleAssetType]  | Params: id (path)
- **DELETE** `/compatibility/flexible_asset_types/{id}` [FlexibleAssetType]  | Params: id (path)
- **GET** `/compatibility/flexible_asset_types/{typeId}/relationships/flexible_asset_fields` [FlexibleAssetType]  | Params: typeId (path), id (query), page[number] (query), page[size] (query), include (query), sort (query)
- **POST** `/compatibility/flexible_asset_types/{typeId}/relationships/flexible_asset_fields` [FlexibleAssetType]  | Params: typeId (path)
- **GET** `/compatibility/flexible_asset_types/{typeId}/relationships/flexible_asset_fields/{fieldId}` [FlexibleAssetType]  | Params: typeId (path), fieldId (path)
- **POST** `/compatibility/flexible_assets` [FlexibleAsset] 
- **GET** `/compatibility/flexible_assets` [FlexibleAsset]  | Params: filter[organization-id] (query), filter[flexible-asset-type-id] (query), filter[name] (query), page[number] (query), page[size] (query), include (query), sort (query)
- **PATCH** `/compatibility/flexible_assets` [FlexibleAsset] 
- **DELETE** `/compatibility/flexible_assets` [FlexibleAsset] Bulk delete flexible assets following IT Glue API specification.
Accepts an array of flexible asset delete objects with IDs inside attributes.
- **GET** `/compatibility/flexible_assets/{id}` [FlexibleAsset]  | Params: id (path), include (query)
- **DELETE** `/compatibility/flexible_assets/{id}` [FlexibleAsset]  | Params: id (path)
- **PATCH** `/compatibility/flexible_assets/{id}` [FlexibleAsset]  | Params: id (path)
- **POST** `/compatibility/organizations/{orgId}/relationships/flexible_assets` [FlexibleAsset]  | Params: orgId (path)
- **POST** `/v2/applicationuser` [User] Create a new user
- **GET** `/v2/applicationuser/{id}` [User] Get a specific user by ID | Params: id (path)
- **PUT** `/v2/applicationuser/{id}` [User] Update an existing user | Params: id (path)
- **PATCH** `/v2/applicationuser/{id}` [User] Apply partial updates to an existing user using JSON Patch | Params: id (path), companyId (query)
- **DELETE** `/v2/applicationuser/{id}` [User] Delete a user by ID (soft delete) | Params: id (path), companyId (query)
- **POST** `/v2/archiveitem` [ArchiveItem] Create a new archive item (without attachment upload). Use separate endpoint for file upload later.
- **GET** `/v2/archiveitem/{archiveId}/{itemId}` [ArchiveItem] Get a single archive item by archiveId (folder) and itemId | Params: archiveId (path), itemId (path)
- **PUT** `/v2/archiveitem/{archiveId}/{itemId}` [ArchiveItem] Full update of archive item | Params: archiveId (path), itemId (path)
- **PATCH** `/v2/archiveitem/{archiveId}/{itemId}` [ArchiveItem] JSON-Patch partial update | Params: archiveId (path), itemId (path)
- **DELETE** `/v2/archiveitem/{archiveId}/{itemId}` [ArchiveItem]  | Params: archiveId (path), itemId (path)
- **POST** `/v2/article` [Article] Create a new article
- **GET** `/v2/article/{articleId}` [Article] Get an article by ID | Params: articleId (path)
- **PUT** `/v2/article/{articleId}` [Article] Update an article | Params: articleId (path)
- **PATCH** `/v2/article/{articleId}` [Article] Partially update an article using JSON Patch | Params: articleId (path)
- **DELETE** `/v2/article/{articleId}` [Article] Delete an article (soft delete) | Params: articleId (path)
- **POST** `/v2/assessment/import-template` [Assessment] Import questions from an assessment template into another assessment.
- **POST** `/v2/assessment/upload` [Assessment] Upload an assessment Excel (.xlsx) file and import its questions into an assessment.
- **POST** `/v2/catalog` [Catalog] 
- **GET** `/v2/catalog/{id}` [Catalog]  | Params: id (path)
- **PUT** `/v2/catalog/{id}` [Catalog]  | Params: id (path)
- **PATCH** `/v2/catalog/{id}` [Catalog]  | Params: id (path)
- **DELETE** `/v2/catalog/{id}` [Catalog]  | Params: id (path)
- **POST** `/v2/catalogquestion` [CatalogQuestion] 
- **GET** `/v2/catalogquestion/{id}` [CatalogQuestion]  | Params: id (path), companyId (query)
- **PUT** `/v2/catalogquestion/{id}` [CatalogQuestion]  | Params: id (path)
- **PATCH** `/v2/catalogquestion/{id}` [CatalogQuestion]  | Params: id (path), companyId (query)
- **DELETE** `/v2/catalogquestion/{id}` [CatalogQuestion]  | Params: id (path), companyId (query)
- **POST** `/v2/certificate` [Certificate] 
- **GET** `/v2/certificate/{id}` [Certificate]  | Params: id (path)
- **PUT** `/v2/certificate/{id}` [Certificate]  | Params: id (path)
- **PATCH** `/v2/certificate/{id}` [Certificate]  | Params: id (path)
- **DELETE** `/v2/certificate/{id}` [Certificate]  | Params: id (path)
- **POST** `/v2/company` [Company] Create a new company
- **GET** `/v2/company/{id}` [Company] Get a company by ID (restricted to current tenant's company) | Params: id (path)
- **PUT** `/v2/company/{id}` [Company] Update an existing company | Params: id (path)
- **PATCH** `/v2/company/{id}` [Company] Apply partial updates to an existing company using JSON Patch | Params: id (path)
- **DELETE** `/v2/company/{id}` [Company] Delete a company | Params: id (path)
- **POST** `/v2/companygroup` [CompanyGroup] Create a new company group
- **GET** `/v2/companygroup/{companyGroupId}` [CompanyGroup] Get a company group by ID | Params: companyGroupId (path)
- **PUT** `/v2/companygroup/{companyGroupId}` [CompanyGroup] Update an existing company group | Params: companyGroupId (path)
- **PATCH** `/v2/companygroup/{companyGroupId}` [CompanyGroup] Partially update a company group | Params: companyGroupId (path)
- **DELETE** `/v2/companygroup/{companyGroupId}` [CompanyGroup] Delete a company group | Params: companyGroupId (path)
- **POST** `/v2/companygroupcompany` [CompanyGroupCompany] Create a new company group company
- **GET** `/v2/companygroupcompany/{companyGroupId}/{companyId}` [CompanyGroupCompany] Get a company group company by company group ID and company ID | Params: companyGroupId (path), companyId (path)
- **DELETE** `/v2/companygroupcompany/{companyGroupId}/{companyId}` [CompanyGroupCompany] Delete a company group company | Params: companyGroupId (path), companyId (path)
- **POST** `/v2/course` [Course] Create a new course
- **GET** `/v2/course/{id}` [Course] Get a specific course by ID | Params: id (path)
- **PUT** `/v2/course/{id}` [Course] Update an existing course | Params: id (path)
- **PATCH** `/v2/course/{id}` [Course] Apply partial updates to an existing course using JSON Patch | Params: id (path)
- **DELETE** `/v2/course/{id}` [Course] Delete a course | Params: id (path)
- **POST** `/v2/courseenrollment` [CourseEnrollment] Enroll a user in a course
- **GET** `/v2/courseenrollment/course/{courseId}/user/{userId}` [CourseEnrollment] Get user's enrollment in a specific course | Params: courseId (path), userId (path)
- **POST** `/v2/courseenrollment/{enrollmentId}/complete` [CourseEnrollment] Mark a course as completed for a user | Params: enrollmentId (path)
- **PATCH** `/v2/courseenrollment/{id}` [CourseEnrollment] Apply partial updates to an existing course enrollment using JSON Patch | Params: id (path)
- **POST** `/v2/courselesson` [CourseLesson] Create a new course lesson
- **GET** `/v2/courselesson/{courseLessonId}` [CourseLesson] Get a course lesson by ID | Params: courseLessonId (path), companyId (query)
- **PUT** `/v2/courselesson/{courseLessonId}` [CourseLesson] Update a course lesson | Params: courseLessonId (path)
- **PATCH** `/v2/courselesson/{courseLessonId}` [CourseLesson] Partially update a course lesson using JSON Patch | Params: courseLessonId (path), companyId (query)
- **DELETE** `/v2/courselesson/{courseLessonId}` [CourseLesson] Delete a course lesson (soft delete) | Params: courseLessonId (path), companyId (query)
- **POST** `/v2/courselessonhistory` [CourseLessonHistory] Create a new course lesson history record
- **GET** `/v2/courselessonhistory/{courseId}/{applicationUserId}/{courseLessonId}` [CourseLessonHistory] Get a course lesson history record by composite key | Params: courseId (path), applicationUserId (path), courseLessonId (path)
- **PUT** `/v2/courselessonhistory/{courseId}/{applicationUserId}/{courseLessonId}` [CourseLessonHistory] Update a course lesson history record | Params: courseId (path), applicationUserId (path), courseLessonId (path)
- **PATCH** `/v2/courselessonhistory/{courseId}/{applicationUserId}/{courseLessonId}` [CourseLessonHistory] Partially update a course lesson history record using JSON Patch | Params: courseId (path), applicationUserId (path), courseLessonId (path), companyId (query)
- **DELETE** `/v2/courselessonhistory/{courseId}/{applicationUserId}/{courseLessonId}` [CourseLessonHistory] Delete a course lesson history record (soft delete) | Params: courseId (path), applicationUserId (path), courseLessonId (path), companyId (query)
- **POST** `/v2/domain` [Domain] Create a new company domain
- **GET** `/v2/domain/{id}` [Domain] Get a specific company domain by ID | Params: id (path)
- **PUT** `/v2/domain/{id}` [Domain] Update a company domain | Params: id (path)
- **PATCH** `/v2/domain/{id}` [Domain] Partially update a company domain | Params: id (path), companyId (query)
- **DELETE** `/v2/domain/{id}` [Domain] Delete a company domain (soft delete) | Params: id (path), companyId (query)
- **POST** `/v2/endpoint` [Endpoint] Creates an endpoint
- **GET** `/v2/endpoint/id/{endpointId}` [Endpoint] Gets an endpoint by its ID | Params: endpointId (path)
- **PUT** `/v2/endpoint/id/{endpointId}` [Endpoint] Replaces endpoint data with the supplied values. Not including a value will result in it being removed. | Params: endpointId (path)
- **PATCH** `/v2/endpoint/id/{endpointId}` [Endpoint] Patches an endpoint using the JSONPatch format. | Params: endpointId (path)
- **DELETE** `/v2/endpoint/id/{endpointId}` [Endpoint] Deletes an endpoint by its ID | Params: endpointId (path)
- **GET** `/v2/endpoint/{machineName}/{manufacturer}` [Endpoint] Gets an endpoint by it's machine name and manufacturer | Params: manufacturer (path), machineName (path)
- **GET** `/v2/endpoint/{machineName}/{manufacturer}/custom-property/{customPropertyName}` [EndpointCustomProperty] Gets a custom property for an point endpoint by the name of 
the property and the endpoint's machine name and manufacturer | Params: machineName (path), manufacturer (path), customPropertyName (path)
- **PUT** `/v2/endpoint/{manufacturer}/{machineName}` [Endpoint] Replaces endpoint data with the supplied values. Not including a value will result in it being removed. | Params: manufacturer (path), machineName (path)
- **PATCH** `/v2/endpoint/{manufacturer}/{machineName}` [Endpoint] Patches an endpoint using the JSONPatch format. | Params: manufacturer (path), machineName (path)
- **DELETE** `/v2/endpoint/{manufacturer}/{machineName}` [Endpoint] Deletes an endpoint | Params: machineName (path), manufacturer (path)
- **PUT** `/v2/endpoint/{manufacturer}/{machineName}/custom-property/{customPropertyName}` [EndpointCustomProperty] Replaces endpoint custom property data with the supplied values. Not including a value will result in the value being set to default or null. | Params: machineName (path), manufacturer (path), customPropertyName (path)
- **PATCH** `/v2/endpoint/{manufacturer}/{machineName}/custom-property/{customPropertyName}` [EndpointCustomProperty] Patches an endpoint using the JSONPatch format. | Params: machineName (path), manufacturer (path), customPropertyName (path)
- **DELETE** `/v2/endpoint/{manufacturer}/{machineName}/custom-property/{customPropertyName}` [EndpointCustomProperty] Deletes an endpoint custom property by the machine name and manufacturer of the endpoing
and the custom property name. | Params: machineName (path), manufacturer (path), customPropertyName (path)
- **POST** `/v2/endpoint/{manufacturer}/{machineName}/update-warranty` [Endpoint] Triggers an asyncronous warranty update for the found endpoint. | Params: manufacturer (path), machineName (path)
- **GET** `/v2/endpoint/{serialNumber}` [Endpoint] Get an endpoint by it's serial number | Params: serialNumber (path)
- **PUT** `/v2/endpoint/{serialNumber}` [Endpoint] Replaces endpoint data with the supplied values. Not including a value will result in it being removed.    /// | Params: serialNumber (path)
- **PATCH** `/v2/endpoint/{serialNumber}` [Endpoint] Patches an endpoint using the JSONPatch format. | Params: serialNumber (path)
- **DELETE** `/v2/endpoint/{serialNumber}` [Endpoint] Deletes an endpoint | Params: serialNumber (path)
- **POST** `/v2/endpoint/{serialNumber}/custom-property` [EndpointCustomProperty] Creates an endpoint custom property for the specified endpoint. | Params: serialNumber (path)
- **GET** `/v2/endpoint/{serialNumber}/custom-property/{customPropertyName}` [EndpointCustomProperty] Get an endpoint custom property by the associated endpoint's serial number
and the name of the custom property | Params: serialNumber (path), customPropertyName (path)
- **PUT** `/v2/endpoint/{serialNumber}/custom-property/{customPropertyName}` [EndpointCustomProperty] Replaces an endpoint custom property with the supplied values. 
Not including a value will result the the property of the custom property 
being set to null.    
/// | Params: serialNumber (path), customPropertyName (path)
- **PATCH** `/v2/endpoint/{serialNumber}/custom-property/{customPropertyName}` [EndpointCustomProperty] Patches an endpoint custom property using the JSONPatch format. https://jsonpatch.com/ | Params: serialNumber (path), customPropertyName (path)
- **DELETE** `/v2/endpoint/{serialNumber}/custom-property/{customPropertyName}` [EndpointCustomProperty] Deletes an endpoint by the endpoint serial number and the name of the custom property. | Params: serialNumber (path), customPropertyName (path)
- **POST** `/v2/endpoint/{serialNumber}/update-warranty` [Endpoint] Triggers an asyncronous warranty update for the found endpoint. | Params: serialNumber (path)
- **POST** `/v2/endpointapplication` [EndpointApplication] Create a new endpoint application
- **GET** `/v2/endpointapplication/{id}` [EndpointApplication] Get an endpoint application by ID | Params: id (path)
- **PUT** `/v2/endpointapplication/{id}` [EndpointApplication] Update an endpoint application | Params: id (path)
- **PATCH** `/v2/endpointapplication/{id}` [EndpointApplication] Partially update an endpoint application | Params: id (path)
- **DELETE** `/v2/endpointapplication/{id}` [EndpointApplication] Delete an endpoint application | Params: id (path)
- **POST** `/v2/feedback` [Feedback] 
- **GET** `/v2/feedback/{id}` [Feedback]  | Params: id (path)
- **PUT** `/v2/feedback/{id}` [Feedback]  | Params: id (path)
- **PATCH** `/v2/feedback/{id}` [Feedback]  | Params: id (path)
- **DELETE** `/v2/feedback/{id}` [Feedback]  | Params: id (path)
- **POST** `/v2/flexible-asset` [FlexibleAsset] Create a new flexible asset
- **POST** `/v2/flexible-asset-field` [FlexibleAssetField] Create a new flexible asset field
- **GET** `/v2/flexible-asset-field/{id}` [FlexibleAssetField] Get a flexible asset field by ID | Params: id (path)
- **POST** `/v2/flexible-asset-type` [FlexibleAssetType] Create a new flexible asset type with optional fields
- **GET** `/v2/flexible-asset-type/{id}` [FlexibleAssetType] Get a flexible asset type by ID | Params: id (path), includeFields (query)
- **PATCH** `/v2/flexible-asset-type/{id}` [FlexibleAssetType] Apply partial updates to an existing flexible asset type using JSON Patch | Params: id (path)
- **DELETE** `/v2/flexible-asset-type/{id}` [FlexibleAssetType] Delete a flexible asset type | Params: id (path)
- **GET** `/v2/flexible-asset/{id}` [FlexibleAsset] Get a flexible asset by ID | Params: id (path)
- **PATCH** `/v2/flexible-asset/{id}` [FlexibleAsset] Apply partial updates to an existing flexible asset using JSON Patch | Params: id (path)
- **DELETE** `/v2/flexible-asset/{id}` [FlexibleAsset] Delete a flexible asset | Params: id (path)
- **POST** `/v2/media` [Media] Create a new media item from JSON data
- **POST** `/v2/media/upload` [Media] Upload a media file | Params: description (query)
- **GET** `/v2/media/{id}` [Media] Get a specific media item by ID | Params: id (path)
- **PUT** `/v2/media/{id}` [Media] Update an existing media item | Params: id (path)
- **PATCH** `/v2/media/{id}` [Media] Partially update a media item using JSON Patch | Params: id (path)
- **DELETE** `/v2/media/{id}` [Media] Soft delete a media item | Params: id (path)
- **POST** `/v2/menu` [Menu] Create a new menu
- **GET** `/v2/menu/{menuId}` [Menu] Get a menu by ID | Params: menuId (path)
- **PUT** `/v2/menu/{menuId}` [Menu] Update a menu | Params: menuId (path)
- **PATCH** `/v2/menu/{menuId}` [Menu] Partially update a menu using JSON Patch | Params: menuId (path)
- **DELETE** `/v2/menu/{menuId}` [Menu] Delete a menu (soft delete) | Params: menuId (path)
- **GET** `/v2/odata/archiveitem` [ArchiveItem] Gets archive items with OData query support
- **GET** `/v2/odata/archiveitem/$count` [ArchiveItem] Gets archive items with OData query support
- **GET** `/v2/odata/article` [Article] Gets articles
- **GET** `/v2/odata/article/$count` [Article] Gets articles
- **GET** `/v2/odata/assessment` [Assessment] Get assessments with OData query capabilities
- **GET** `/v2/odata/assessment/$count` [Assessment] Get assessments with OData query capabilities
- **GET** `/v2/odata/catalog` [Catalog] Get company catalog items with OData query support
- **GET** `/v2/odata/catalog/$count` [Catalog] Get company catalog items with OData query support
- **GET** `/v2/odata/catalogquestion` [CatalogQuestion] 
- **GET** `/v2/odata/catalogquestion/$count` [CatalogQuestion] 
- **GET** `/v2/odata/certificate` [Certificate] 
- **GET** `/v2/odata/certificate/$count` [Certificate] 
- **GET** `/v2/odata/company` [Company] Gets companies
- **GET** `/v2/odata/company/$count` [Company] Gets companies
- **GET** `/v2/odata/companygroup` [CompanyGroup] Gets company groups
- **GET** `/v2/odata/companygroup/$count` [CompanyGroup] Gets company groups
- **GET** `/v2/odata/companygroupcompany` [CompanyGroupCompany] Gets company group companies
- **GET** `/v2/odata/companygroupcompany/$count` [CompanyGroupCompany] Gets company group companies
- **GET** `/v2/odata/course` [Course] Gets courses
- **GET** `/v2/odata/course/$count` [Course] Gets courses
- **GET** `/v2/odata/courseenrollment` [CourseEnrollment] Gets course enrollments
- **GET** `/v2/odata/courseenrollment/$count` [CourseEnrollment] Gets course enrollments
- **GET** `/v2/odata/courselesson` [CourseLesson] Gets course lessons
- **GET** `/v2/odata/courselesson/$count` [CourseLesson] Gets course lessons
- **GET** `/v2/odata/courselessonhistory` [CourseLessonHistory] Gets course lesson history records
- **GET** `/v2/odata/courselessonhistory/$count` [CourseLessonHistory] Gets course lesson history records
- **GET** `/v2/odata/domain` [Domain] Get company domains with OData query support
- **GET** `/v2/odata/domain/$count` [Domain] Get company domains with OData query support
- **GET** `/v2/odata/endpoint` [Endpoint] Gets endpoints
- **GET** `/v2/odata/endpoint/$count` [Endpoint] Gets endpoints
- **GET** `/v2/odata/endpointapplication` [EndpointApplication] Gets endpoint applications
- **GET** `/v2/odata/endpointapplication/$count` [EndpointApplication] Gets endpoint applications
- **GET** `/v2/odata/endpointcustomproperty` [EndpointCustomProperty] Gets endpoint custom properties
- **GET** `/v2/odata/endpointcustomproperty/$count` [EndpointCustomProperty] Gets endpoint custom properties
- **GET** `/v2/odata/feedback` [Feedback] 
- **GET** `/v2/odata/feedback/$count` [Feedback] 
- **GET** `/v2/odata/flexibleasset` [FlexibleAsset] Gets flexible assets
- **GET** `/v2/odata/flexibleasset/$count` [FlexibleAsset] Gets flexible assets
- **GET** `/v2/odata/flexibleassetfield` [FlexibleAssetField] Gets flexible asset fields
- **GET** `/v2/odata/flexibleassetfield/$count` [FlexibleAssetField] Gets flexible asset fields
- **GET** `/v2/odata/flexibleassettype` [FlexibleAssetType] Gets flexible asset types
- **GET** `/v2/odata/flexibleassettype/$count` [FlexibleAssetType] Gets flexible asset types
- **GET** `/v2/odata/media` [Media] Get media items with OData query capabilities
- **GET** `/v2/odata/media/$count` [Media] Get media items with OData query capabilities
- **GET** `/v2/odata/menu` [Menu] Get menus with OData query capabilities
- **GET** `/v2/odata/menu/$count` [Menu] Get menus with OData query capabilities
- **GET** `/v2/odata/product` [Product] Get products with OData query capabilities
- **GET** `/v2/odata/product/$count` [Product] Get products with OData query capabilities
- **GET** `/v2/odata/quickstart` [Quickstart] Gets quickstarts
- **GET** `/v2/odata/quickstart/$count` [Quickstart] Gets quickstarts
- **GET** `/v2/odata/service` [Service] Gets services
- **GET** `/v2/odata/service/$count` [Service] Gets services
- **GET** `/v2/odata/serviceinstall` [ServiceInstall] Gets service installations
- **GET** `/v2/odata/serviceinstall/$count` [ServiceInstall] Gets service installations
- **GET** `/v2/odata/token` [Token] Get tokens from Company.Settings with OData query support
- **GET** `/v2/odata/token/$count` [Token] Get tokens from Company.Settings with OData query support
- **GET** `/v2/odata/user` [User] Gets users
- **GET** `/v2/odata/user/$count` [User] Gets users
- **POST** `/v2/product` [Product] Create a new product
- **GET** `/v2/product/{id}` [Product] Get a product by ID | Params: id (path)
- **PUT** `/v2/product/{id}` [Product] Update a product | Params: id (path)
- **PATCH** `/v2/product/{id}` [Product] Partially update a product | Params: id (path)
- **DELETE** `/v2/product/{id}` [Product] Delete a product (soft delete) | Params: id (path)
- **POST** `/v2/quickstart` [Quickstart] Create a new quickstart
- **GET** `/v2/quickstart/{quickstartId}` [Quickstart] Get a quickstart by ID | Params: quickstartId (path)
- **PUT** `/v2/quickstart/{quickstartId}` [Quickstart] Update a quickstart | Params: quickstartId (path)
- **PATCH** `/v2/quickstart/{quickstartId}` [Quickstart] Partially update a quickstart using JSON Patch | Params: quickstartId (path)
- **DELETE** `/v2/quickstart/{quickstartId}` [Quickstart] Delete a quickstart (soft delete) | Params: quickstartId (path)
- **POST** `/v2/service` [Service] Create a new service
- **GET** `/v2/service/{id}` [Service] Get a service by ID | Params: id (path)
- **PUT** `/v2/service/{id}` [Service] Update a service | Params: id (path)
- **DELETE** `/v2/service/{id}` [Service] Delete a service | Params: id (path)
- **PATCH** `/v2/service/{id}` [Service] Partially update a service | Params: id (path)
- **POST** `/v2/serviceinstall` [ServiceInstall] Create a new service installation
- **GET** `/v2/serviceinstall/{endpointId}/{serviceId}` [ServiceInstall] Get a service installation by its composite key | Params: endpointId (path), serviceId (path)
- **PUT** `/v2/serviceinstall/{endpointId}/{serviceId}` [ServiceInstall] Update a service installation | Params: endpointId (path), serviceId (path)
- **PATCH** `/v2/serviceinstall/{endpointId}/{serviceId}` [ServiceInstall] Patch a service installation | Params: endpointId (path), serviceId (path)
- **DELETE** `/v2/serviceinstall/{endpointId}/{serviceId}` [ServiceInstall] Delete a service installation | Params: endpointId (path), serviceId (path)
- **GET** `/v2/token` [Token] Get all tokens for a company or partner | Params: companyId (query)
- **POST** `/v2/token` [Token] Create or update a token
- **GET** `/v2/token/{tokenName}` [Token] Get a specific token by composite key (companyId + tokenName) | Params: companyId (query), tokenName (path)
- **PUT** `/v2/token/{tokenName}` [Token] Update a token value using composite key (companyId + tokenName) | Params: tokenName (path), companyId (query)
- **PATCH** `/v2/token/{tokenName}` [Token] Partially update a token using composite key (companyId + tokenName) | Params: tokenName (path), companyId (query)
- **DELETE** `/v2/token/{tokenName}` [Token] Delete a token using composite key (companyId + tokenName) | Params: tokenName (path), companyId (query)
- **POST** `/v2/user` [User] Create a new user
- **GET** `/v2/user/{id}` [User] Get a specific user by ID | Params: id (path)
- **PUT** `/v2/user/{id}` [User] Update an existing user | Params: id (path)
- **PATCH** `/v2/user/{id}` [User] Apply partial updates to an existing user using JSON Patch | Params: id (path), companyId (query)
- **DELETE** `/v2/user/{id}` [User] Delete a user by ID (soft delete) | Params: id (path), companyId (query)