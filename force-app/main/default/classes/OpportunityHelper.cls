public with sharing class OpportunityHelper {

    private static Boolean isAssigningPrimaryContact = false;
    
    public static void setType(List<Opportunity> newOpps) {
        for (Opportunity opp : newOpps) {
            if (opp.Type == null){
                opp.Type = 'New Customer';
            }        
        }
    }

    public static void validateCloseOpportunity(List<Opportunity> opps) {
        for (Opportunity opp : opps){
            if (opp.IsClosed){
                opp.addError('Cannot delete closed opportunity');
            }
        }
    }

    public static void insertTask(List<Opportunity> opps) {
        List<Task> tasks = new List<Task>();

        for (Opportunity opp : opps) {
            Task tsk = new Task();
            tsk.Subject = 'Call Primary Contact';
            tsk.WhatId = opp.Id;
            tsk.OwnerId = opp.OwnerId;
            tsk.ActivityDate = Date.today().addDays(3);
            
            // Only set WhoId if Primary_Contact__c exists
            if (opp.Primary_Contact__c != null) {
                tsk.WhoId = opp.Primary_Contact__c;
            }
            
            tasks.add(tsk);
        }

        if (!tasks.isEmpty()) {
            insert tasks;
        }
    }

    public static void updateDescriptionFromStage(List<Opportunity> opps) {
        Map<Id, Opportunity> oldOppsMap = (Map<Id, Opportunity>)Trigger.oldMap;

        for (Opportunity opp : opps){
            Opportunity oldOpp = oldOppsMap.get(opp.Id);
        
            if (opp.StageName != null && oldOpp != null && opp.StageName != oldOpp.StageName) {
                if (opp.Description == null) {
                    opp.Description = '';
                }
                opp.Description += '\nStage Change:' + opp.StageName + DateTime.now().format();
            }   
        }
    }

    public static void notifyOwnersOpportunityDeleted(List<Opportunity> opps) {
        Set<Id> ownerIds = new Set<Id>();
        for (Opportunity opp : opps) {
            ownerIds.add(opp.OwnerId);
        }
        
        Map<Id, User> ownerMap = new Map<Id, User>(
            [SELECT Id, Email FROM User WHERE Id IN :ownerIds]
        );
        
        List<Messaging.SingleEmailMessage> mails = new List<Messaging.SingleEmailMessage>();
        for (Opportunity opp : opps) {
            User owner = ownerMap.get(opp.OwnerId);
            if (owner != null && String.isNotBlank(owner.Email)) {
                Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
                mail.setToAddresses(new String[] {owner.Email});
                mail.setSubject('Opportunity Deleted: ' + opp.Name);
                mail.setPlainTextBody('Your Opportunity: ' + opp.Name + ' has been deleted.');
                mails.add(mail);
            }
        }
        
        if (!mails.isEmpty()) {
            try {
                Messaging.sendEmail(mails);
            } catch (Exception e) {
                System.debug('Exception: ' + e.getMessage());
            }
        }
    }

    public static void assignPrimaryContact(Map<Id, Opportunity> oppNewMap) {
        // Prevent recursion
        if (isAssigningPrimaryContact) {
            return;
        }
        
        try {
            isAssigningPrimaryContact = true;
            
            if (oppNewMap == null || oppNewMap.isEmpty()) {
                return;
            }
            
            // Collect Account IDs
            Set<Id> accountIds = new Set<Id>();
            for (Opportunity opp : oppNewMap.values()) {
                if (opp.AccountId != null && opp.Primary_Contact__c == null) {
                    accountIds.add(opp.AccountId);
                }
            }
            
            if (accountIds.isEmpty()) {
                return;
            }
            
            // Single SOQL query - bulkified
            Map<Id, Contact> accountIdToContact = new Map<Id, Contact>();
            for (Contact con : [SELECT Id, AccountId 
                            FROM Contact 
                            WHERE Title = 'VP Sales' 
                            AND AccountId IN :accountIds]) {
                // Only store first VP Sales contact per account
                if (!accountIdToContact.containsKey(con.AccountId)) {
                    accountIdToContact.put(con.AccountId, con);
                }
            }
            
            // Build list of opportunities to update
            Map<Id, Opportunity> oppMap = new Map<Id, Opportunity>();
            for (Opportunity opp : oppNewMap.values()) {
                if (opp.Primary_Contact__c == null && 
                    opp.AccountId != null && 
                    accountIdToContact.containsKey(opp.AccountId)) {
                    
                    Contact primaryContact = accountIdToContact.get(opp.AccountId);
                    Opportunity oppToUpdate = new Opportunity(
                        Id = opp.Id,
                        Primary_Contact__c = primaryContact.Id
                    );
                    oppMap.put(opp.Id, oppToUpdate);
                }
            }
            
            // Only update if there are records to update
            if (!oppMap.isEmpty()) {
                update oppMap.values();
            }
            
        } catch (DmlException e) {
            System.debug(LoggingLevel.ERROR, 'DML error in assignPrimaryContact: ' + e.getMessage());
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in assignPrimaryContact: ' + e.getMessage());
            throw e;
        } finally {
            isAssigningPrimaryContact = false;
        }
    }

    public static void validateAmount(List<Opportunity> opps) {
         try {
            if (opps == null || opps.isEmpty()) {
                return;
            }

            for (Opportunity opp : opps) {
                if (opp.Amount <= 5000) {
                    opp.addError('Opportunity amount must be greater than 5000');
                }
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in validateAmount: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e; // Re-throw to ensure trigger fails properly
        }
    }

    public static void deleteCloseWonOpps(List<Opportunity> opps) {
        try {
            if (opps == null || opps.isEmpty()) {
                return;
            }

            Set<Id> accountIds = new Set<Id>();
            for (Opportunity opp : opps) {
                if (opp.AccountId != null) {
                    accountIds.add(opp.AccountId);
                }
            }
            
            Map<Id, Account> accountMap = new Map<Id, Account>([
                SELECT Id, Industry
                FROM Account
                WHERE Id IN :accountIds
            ]);
                
            for (Opportunity opp : opps) {
                Account relatedAccount = accountMap.get(opp.AccountId);
                
                if (relatedAccount != null && 
                    relatedAccount.Industry == 'Banking' && 
                    opp.StageName == 'Closed Won') {
                        opp.addError('Cannot delete closed opportunity for a banking account that is won');
                }
            }
        } catch (QueryException e) {
            System.debug(LoggingLevel.ERROR, 'Query error in deleteCloseWonOpps: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in deleteCloseWonOpps: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }

    public static void setPrimaryContactCEO(List<Opportunity> opps) {
        try {
            if (opps == null || opps.isEmpty()) {
                return;
            }
            
            Set<Id> accountIds = new Set<Id>();
            for (Opportunity opp : opps) {
                if (opp.AccountId != null) {
                    accountIds.add(opp.AccountId);
                }
            }

            Map<Id, Account> idToAccs = new Map<Id, Account>([
                SELECT Id, 
                    (SELECT Id
                    FROM Contacts
                    WHERE Title = 'CEO'
                    LIMIT 1)
                FROM Account
                WHERE Id IN :accountIds
            ]);

            for (Opportunity opp : opps) {
                if (opp.AccountId != null && idToAccs.containsKey(opp.AccountId)) {
                    Account relatedAccount = idToAccs.get(opp.AccountId);

                    if (relatedAccount.Contacts != null && !relatedAccount.Contacts.isEmpty()) {
                        Contact relatedAccPrimaryCon = relatedAccount.Contacts[0];
                        opp.Primary_Contact__c = relatedAccPrimaryCon.Id;
                    }    
                }
            }
        } catch (QueryException e) {
            System.debug(LoggingLevel.ERROR, 'Query error in setPrimaryContact: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error in setPrimaryContact: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }
}