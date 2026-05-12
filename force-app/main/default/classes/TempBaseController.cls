public class TempBaseController {
        
    /**
     * テンプレートに紐付くタスクリスト取得
     * */
    @AuraEnabled
    public static List<TaskMaster__c> getTaskList(Id recordId){
        try{
            List<TaskMaster__c> taskList = new List<TaskMaster__c>();
            List<TaskMaster__c> mainTaskList = getMainTaskList(recordId);
            for(TaskMaster__c mt:mainTaskList){
                taskList.add(mt);
                List<TaskMaster__c> subTaskList = getSubTaskList(recordId, mt.Id);
                taskList.addAll(subTaskList);
            }
            return taskList;
        }catch(Exception e){
            throw e;
        }
    }
    
    /**
     * テンプレートに紐付くMainタスクリスト取得
     * */
    public static List<TaskMaster__c> getMainTaskList(Id recordId){
        List<TaskMaster__c> mainTaskList = [SELECT Template__c, Id, RecordType.Name, selectedFlg__c, Name, days__c, text1__c, TaskMaster__c, DisplayNum__c
                                            FROM TaskMaster__c
                                            WHERE Template__c = :recordId
                                            AND RecordType.Name = 'Main'
                                           order by DisplayNum__c];
		return mainTaskList;
    }
    
    /**
     * テンプレートに紐付くSubタスクリスト取得
     * */
    public static List<TaskMaster__c> getSubTaskList(Id recordId, Id mainTaskId){
        List<TaskMaster__c> subTaskList = [SELECT Template__c, Id, RecordType.Name, selectedFlg__c, Name, days__c, text1__c, TaskMaster__c, DisplayNum__c
                                           FROM TaskMaster__c
                                           WHERE TaskMaster__c = :mainTaskId
                                           AND RecordType.Name = 'Sub'
                                           order by DisplayNum__c];
		return subTaskList;
    }
    
    /**
     * タスク更新
     * */
    @AuraEnabled
    public static List<TaskMaster__c> setTasks(List<TaskMaster__c> taskList, Id recordId, List<Id> delList){
        try{
            //削除するタスクをタスクマスタから削除
            deleteTask(delList);
            
            Id mainRecId = getRecIdinTM('Main');
            Id subRecId = getRecIdinTM('Sub');
            Id mainId = null;
            List<TaskMaster__c> tmList = new List<TaskMaster__c>();
            Integer cnt=0;
            for(TaskMaster__c t:taskList){
                t.put('Template__c',recordId);
                t.put('selectedFlg__c',false);
                t.put('DisplayNum__c',cnt++);
                t.put('TaskMaster__c',mainId);
                
                upsert t;
                
                //mainの場合Id取得
                if(t.get('RecordTypeId').equals(mainRecId)){
                    mainId = t.Id;
                }
            }
            return getTaskList(recordId);  
        }catch(Exception e){
            throw new AuraHandledException('TempBaseController.setTasks' + e.getMessage());
        }  
    }
    
    /**
    * タスクマスタのRecordTypeIdを取得
    * */
    public static Id getRecIdinTM(String RecName){
        return Schema.SObjectType.TaskMaster__c.getRecordTypeInfosByDeveloperName()
            .get(RecName).getRecordTypeId();
    }
    
    /**
     * 削除ボタン押下時保持したIdリストでタスク削除
     * */
    public static void deleteTask(List<Id> delList){
        List<TaskMaster__c> deleteList = [SELECT Id, Name 
                                          FROM TaskMaster__c
                                          WHERE Id IN :delList];
        delete deleteList;
    }
    
    /**
     * 初期処理
     * */
    @AuraEnabled
    public static Map<String, Object> initDo(Id recordId){
        try{
            List<Map<String, Object>> initMapList = new List<Map<String, Object>>();
            Map<String, Object> initMap = new Map<String, Object>();
            //初期表示
            initMap.put('taskMasterList',getTaskList(recordId));
            //レコードId取得
            initMap.put('mainRecordTypeId',getRecIdinTM('Main'));
            initMap.put('subRecordTypeId',getRecIdinTM('Sub'));
            return initMap;
        }catch(Exception e){
            throw new AuraHandledException('TempBaseController.initDo' + e.getMessage());
        }
    }
}