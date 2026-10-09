package net.local.vizioremote;
final class SettingPolicy {
    static boolean editable(String type) {return type.equals("T_LIST_V1")||type.equals("T_LIST_X_V1")||type.equals("T_VALUE_V1")||type.equals("T_VALUE_ABS_V1")||type.equals("T_STRING_V1")||type.equals("T_IP_ADDRESS_V1");}
    static boolean pathPart(String s) {return s!=null&&s.matches("[A-Za-z0-9_-]+");}
    static boolean isMenu(String s) {return s.equals("T_MENU_V1")||s.equals("T_MENU_X_V1");}
}
