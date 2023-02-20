public with sharing class GivingScoreBatch extends BatchJob {

    final Boolean fullRun;

    Set<Id> contactIds = new Set<Id>();
    Map<Id, Contact> contactIdToContact = new Map<Id, Contact>();
    Map<Id, Giving_Score__c> contactIdToGivingScore = new Map<Id, Giving_Score__c>();

    public GivingScoreBatch() {
        this(false);
    }

    public GivingScoreBatch(Boolean fullRun) {
        super('GivingScore');
        this.fullRun = fullRun;
    }

    public override Database.QueryLocator start() {
        List<String> contactFields = new List<String> {
            'AccountId', 'AQB__PersonalEmail__c', 'AQB__BusinessEmail__c', 'AQB__OtherEmail__c', 
            'Email', 'AQB__School__c', 'AQB__MaritalStatus__c', 'Phone', 'AQB__BusinessPhone__c', 
            'AQB__AccountPhone__c', 'AQB__Gender__c', 'AQB__PreferredYear__c', 'AQB__DegreeYear__c', 
            'AQB__AccountMailingAddressType__c', 'AQB__BusinessAddressType__c', 'AQB__MailingAddressType__c'
        };

        List<String> givingScoreFields = new List<String> {
            'Contact__c', 'Married_Flag__c', 'Email_Listed_Flag__c',
            'Home_Phone_Listed_Flag__c', 'Business_Phone_Listed_Flag__c', 'Gender__c',
            'Recent_Alumni_Indicator__c', 'Preferred_Graduation_Year__c',
            'Undergrad_Indicator__c', 'Masters_Indicator__c', 'Doctorate_Indicator__c',
            'CFA__c', 'CIT__c', 'CMU__c', 'DC__c', 'Heinz__c', 'MCS__c', 'SCS__c', 'Tepper__c',
            'Three_Years_Ago_Volunteering__c', 'Three_Years_Ago_Events_Attended__c', 'Ung_Mass_Email_Open__c',
            'Currently_Employed__c', 'Home_Address_Listed__c'
        };

        String whereClause = fullRun ? '' : ' Contact__r.Update_Giving_Score__c = TRUE';

        String soqlQuery = QueryBuilder.builder()
            .selectFields(givingScoreFields)
            .selectFields('Contact__r', contactFields)
            .fromObject('Giving_Score__c')
            .whereClause(whereClause)
            .build();

        return Database.getQueryLocator(soqlQuery);
    }

    public void execute(Database.BatchableContext context, List<Giving_Score__c> givingScoreList) {
        List<ObjectFieldHistory> fieldHistoryList = new List<ObjectFieldHistory>();

        for (Giving_Score__c givingScore : givingScoreList) {
            Contact contact = givingScore.Contact__r;
            Id contactId = contact.Id;

            contactIds.add(contactId);
            contactIdToContact.put(contactId, givingScore.Contact__r);
            contactIdToGivingScore.put(contactId, givingScore);
            fieldHistoryList.add(new ObjectFieldHistory(givingScore));
            givingScore.Account__c = contact.AccountId;
        }

        findDemFlags();
        findEducation();
        findSchool();
        findVolunteer();
        findEvents();
        findHomeAddress();
        findOpenRate();
        findEmployment();

        List<Giving_Score__c> updatedGivingScores = ObjectFieldHistory.getChangedObjects(fieldHistoryList);
        updatePartial(updatedGivingScores);
    }

  void findDemFlags() {
    Set<Id> contactsWithSpouse = new Set<Id>();

    for (AQB__RelationshipContact__c relationship : [ SELECT Id, AQB__ContactId__c, AQB__RelatedContactRole__r.Name
            FROM AQB__RelationshipContact__c
            WHERE AQB__ContactId__c IN :contactIds
            WITH SECURITY_ENFORCED ]) {
        String roleName = relationship.AQB__RelatedContactRole__r.Name;

        if (roleName == RelationshipConstant.RELATIONSHIP_SPOUSE || roleName == RelationshipConstant.REVERSE_RELATIONSHIP_SPOUSE) {
            contactsWithSpouse.add(relationship.AQB__ContactId__c);
        }
    }

    for (Id contactId : contactIds) {
        Giving_Score__c givingScore = contactIdToGivingScore.get(contactId);
        Contact contact = contactIdToContact.get(contactId);

        givingScore.Married_Flag__c = (contact.AQB__MaritalStatus__c == 'Married' || contactsWithSpouse.contains(givingScore.Contact__c));
        givingScore.Email_Listed_Flag__c = (contact.AQB__PersonalEmail__c != null || contact.AQB__BusinessEmail__c != null || contact.AQB__OtherEmail__c == null || contact.Email == null);
        givingScore.Home_Phone_Listed_Flag__c = contact.AQB__AccountPhone__c != null;
        givingScore.Business_Phone_Listed_Flag__c = contact.AQB__BusinessPhone__c != null;
        givingScore.Gender__c = contact.AQB__Gender__c;

        if (contact.AQB__PreferredYear__c != null) {
            Integer prefYear = Integer.valueOf(contact.AQB__PreferredYear__c);
            givingScore.Recent_Alumni_Indicator__c = (System.today().year() - prefYear) <= 9;
            givingScore.Preferred_Graduation_Year__c = String.valueOf(prefYear);
        }
        else {
            givingScore.Recent_Alumni_Indicator__c = false;
            givingScore.Preferred_Graduation_Year__c = null;
        }

    }
  }

    void findEducation() {
        Set<Id> contactsWithUndergradDegree = new Set<Id>();
        Set<Id> contactsWithMastersDegree = new Set<Id>();
        Set<Id> contactsWithDoctoralDegree = new Set<Id>();

        for (AQB__Education__c degree : [
          SELECT AQB__ContactId__c, AQB__DegreeLevel__c
          FROM AQB__Education__c
          WHERE AQB__ContactId__c IN :contactIds AND RecordTypeId = :EducationConstant.RECORD_TYPE_INSTITUTIONAL
          WITH SECURITY_ENFORCED
          ]) {

          Id contactId = degree.AQB__ContactId__c;
          String degreeLevel = degree?.get(EducationConstant.DEGREE_LEVEL_FIELD)?.toString();

          if (EducationConstant.isUndergraduateDegreeLevel(degreeLevel)) {
              contactsWithUndergradDegree.add(contactId);
          }
          else if (EducationConstant.isMastersDegreeLevel(degreeLevel)) {
              contactsWithMastersDegree.add(contactId);
          }
          else if (EducationConstant.isDoctoralDegreeLevel(degreeLevel)) {
              contactsWithDoctoralDegree.add(contactId);
          }
        }

        for (Id contactId : contactIds) {
            Giving_Score__c givingScore = contactIdToGivingScore.get(contactId);

            givingScore.Undergrad_Indicator__c = contactsWithUndergradDegree.contains(contactId);
            givingScore.Masters_Indicator__c = contactsWithMastersDegree.contains(contactId);
            givingScore.Doctorate_Indicator__c = contactsWithDoctoralDegree.contains(contactId);
        }
    }

    public void findSchool() {
        for (Id contactId : contactIds) {
            Giving_Score__c givingScore = contactIdToGivingScore.get(contactId);
            Contact contact = contactIdToContact.get(contactId);

            givingScore.CFA__c = contact.AQB__School__c == EducationConstant.SCHOOL_CFA;
            givingScore.CIT__c = contact.AQB__School__c == EducationConstant.SCHOOL_CIT;
            givingScore.CMU__c = contact.AQB__School__c == EducationConstant.SCHOOL_MM || contact.AQB__School__c == EducationConstant.SCHOOL_CMU || contact.AQB__School__c == EducationConstant.SCHOOL_LIBRARY || contact.AQB__School__c == 'Printing Management' || contact.AQB__School__c == 'Unspecified';
            givingScore.DC__c = contact.AQB__School__c == EducationConstant.SCHOOL_HUMANITIES || contact.AQB__School__c == 'Dietrich College of H and SS';
            givingScore.Heinz__c = contact.AQB__School__c == EducationConstant.SCHOOL_HEINZ_SCHOOL || contact.AQB__School__c == EducationConstant.SCHOOL_HEINZ_COLLEGE;
            givingScore.MCS__c = contact.AQB__School__c == EducationConstant.SCHOOL_MCS;
            givingScore.SCS__c = contact.AQB__School__c == EducationConstant.SCHOOL_CS;
            givingScore.Tepper__c = contact.AQB__School__c == EducationConstant.SCHOOL_GSIA || contact.AQB__School__c == EducationConstant.SCHOOL_TEPPER || contact.AQB__School__c == EducationConstant.SCHOOL_INDUSTRIAL_MANAGEMENT || contact.AQB__School__c == 'Indust Mgmt (Graphic Comms Mgmt)' || contact.AQB__School__c == EducationConstant.SCHOOL_INDUSTRIES;
        }
    }


  void findVolunteer() {
    Set<Id> contactsWhoVolunteered = new Set<Id>();

    for (AQB__VolunteerPosition__c vp : [
            SELECT Id, AQB__ContactId__c, AQB__StartDate__c, Status__c, AQB__AffiliatedOrganization__c
            FROM AQB__VolunteerPosition__c
            WHERE AQB__StartDate__c >= N_FISCAL_YEARS_AGO:3 AND
            AQB__StartDate__c < THIS_FISCAL_YEAR AND
            Status__c = 'Current' AND
            AQB__ContactId__c IN :contactIds
            WITH SECURITY_ENFORCED ]) {
      contactsWhoVolunteered.add(vp.AQB__ContactId__c);
    }

    for (Id contactId : contactIds) {
        Giving_Score__c givingScore = contactIdToGivingScore.get(contactId);
        givingScore.Three_Years_Ago_Volunteering__c = contactsWhoVolunteered.contains(contactId) ? 1 : 0;
    }

  }

    void findEvents() {
        Set<Id> contactsWhoAttendedEvents = new Set<Id>();

        for (AQB__EventGuest__c eg : [
                SELECT Id, AQB__Contact__c, AQB__Event_Date__c
                FROM AQB__EventGuest__c
                WHERE AQB__Contact__c IN :contactIds AND
                AQB__Event_Date__c >= N_FISCAL_YEARS_AGO:3 AND
                AQB__Event_Date__c < THIS_FISCAL_YEAR AND
                No_Show__c = FALSE AND
                AQB__Event_Registration__c IN (
                        SELECT Id
                        FROM AQB__Registration__c
                        WHERE AQB__Event__r.AQB__Status__c = 'Completed'
                )
                WITH SECURITY_ENFORCED ]) {
          contactsWhoAttendedEvents.add(eg.AQB__Contact__c);
        }

        for (Id contactId : contactIds) {
            Giving_Score__c givingScore = contactIdToGivingScore.get(contactId);
            givingScore.Three_Years_Ago_Events_Attended__c = contactsWhoAttendedEvents.contains(contactId) ? 1 : 0;
        }
    }

    void findOpenRate() {
        List<et4ae5__IndividualEmailResult__c> indEmail = [
          SELECT Id, et4ae5__Contact__c, et4ae5__Opened__c, et4ae5__SendDefinition__r.et4ae5__Number_Delivered__c, et4ae5__SendDefinition__r.et4ae5__DateSent__c
          FROM et4ae5__IndividualEmailResult__c
          WHERE et4ae5__Contact__c IN :contactIds AND
          et4ae5__Opened__c = TRUE AND
          et4ae5__SendDefinition__r.et4ae5__Number_Delivered__c >= 1000 AND
          et4ae5__SendDefinition__r.et4ae5__DateSent__c = LAST_FISCAL_YEAR
          WITH SECURITY_ENFORCED
        ];

        Set<Id> contactsWithOpenEmail = new Set<Id>();

        for (et4ae5__IndividualEmailResult__c er : indEmail) {
          contactsWithOpenEmail.add(er.et4ae5__Contact__c);
        }

        for (Id contactId : contactIds) {
            Giving_Score__c givingScore = contactIdToGivingScore.get(contactId);
            givingScore.Ung_Mass_Email_Open__c = contactsWithOpenEmail.contains(givingScore.Contact__c);
        }

  }


    void findEmployment() {
        Map<Id, Id> contactIdToEmploymentId = new Map<Id, Id>();

        for (AQB__Employment__c em : [
                SELECT Id, AQB__ContactId__c, AQB__BusinessPhone__c, AQB__Status__c, AQB__EndDate__c
                FROM AQB__Employment__c
                WHERE AQB__ContactId__c IN :contactIds
                WITH SECURITY_ENFORCED ]) {
          contactIdToEmploymentId.put(em.AQB__ContactId__c, em.Id);
        }

        for (Id contactId : contactIds) {
            Giving_Score__c givingScore = contactIdToGivingScore.get(contactId);
            givingScore.Currently_Employed__c = contactIdToEmploymentId.containsKey(contactId);
        }

    }

    void findHomeAddress() {
        for (Id contactId : contactIds) {
            Giving_Score__c givingScore = contactIdToGivingScore.get(contactId);
            Contact contact = contactIdToContact.get(contactId);

            Boolean homeAddressListed = contact.AQB__AccountMailingAddressType__c == 'Home' || contact.AQB__BusinessAddressType__c == 'Home' || contact.AQB__MailingAddressType__c == 'Home';
            givingScore.Home_Address_Listed__c = homeAddressListed;
        }
    }

}
