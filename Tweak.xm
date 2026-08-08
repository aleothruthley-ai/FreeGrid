#import <UIKit/UIKit.h>

// ===================================================================
// 1. 头文件声明
// ===================================================================
@interface SBIcon : NSObject
- (NSString *)leafIdentifier;
- (NSString *)applicationBundleIdentifier;
@end

@interface SBIconListView : UIView
- (NSString *)iconLocation;
@end

@interface SBIconListModel : NSObject
- (NSString *)uniqueIdentifier;
- (void)setFixedLocation:(unsigned long long)location forIcon:(id)icon;
@end

// ===================================================================
// 2. 本地自定义位置配置管理器 (Plist)
// ===================================================================
#define PLIST_PATH @"/var/mobile/Library/Preferences/com.freegrid.layout.plist"

// 读取配置
static NSMutableDictionary *GetGridConfig() {
    NSMutableDictionary *config = [NSMutableDictionary dictionaryWithContentsOfFile:PLIST_PATH];
    return config ? config : [NSMutableDictionary dictionary];
}

// 异步写入配置（防卡顿）
static void SaveGridConfig(NSMutableDictionary *config) {
    if (!config) return;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [config writeToFile:PLIST_PATH atomically:YES];
        // 保证 SpringBoard 对该文件拥有读写权限
        [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @0777} ofItemAtPath:PLIST_PATH error:nil];
    });
}

// 获取图标的唯一标识符
static NSString *GetIconID(id icon) {
    if ([icon respondsToSelector:@selector(leafIdentifier)]) {
        return [icon leafIdentifier];
    } else if ([icon respondsToSelector:@selector(applicationBundleIdentifier)]) {
        return [icon applicationBundleIdentifier];
    }
    return nil;
}


// ===================================================================
// 3. 视图层：开放桌面留空权限
// ===================================================================
%hook SBIconListView

- (BOOL)allowsGaps {
    if ([self respondsToSelector:@selector(iconLocation)]) {
        NSString *location = [self iconLocation];
        // Dock 栏绝对不能留空，否则排版会崩溃
        if (location && [location containsString:@"Dock"]) {
            return %orig;
        }
    }
    return YES;
}

%end


// ===================================================================
// 4. 数据模型层：全面接管坐标读写
// ===================================================================
%hook SBIconListModel

- (BOOL)allowsFixedIconLocations {
    return YES;
}

- (long long)fixedIconLocationBehavior {
    return 1;
}

// 【彻底瘫痪自动靠拢与挤压算法】
- (void)compactIcons { }

// 非常关键：这里必须原样返回传入的 icons 数组！如果返回 nil 会触发 NSMutableSet 异常崩溃！
- (id)repairModelByEliminatingGapsInIcons:(id)icons avoidingIcons:(id)avoidingIcons {
    return icons; 
}
- (id)_updateModelByRepairingGapsIfNecessary { return @[]; }
- (id)_updateModelByRepairingGapsIfNecessaryAvoidingIcons:(id)icons { return @[]; }


// 【拦截读取】：当系统排版时，强制从我们的 Plist 中获取坐标
- (unsigned long long)fixedLocationForIcon:(id)icon {
    NSString *listID = [self uniqueIdentifier]; // 获取当前是第几页、哪个文件夹
    NSString *iconID = GetIconID(icon);

    if (listID && iconID) {
        NSDictionary *config = GetGridConfig();
        NSDictionary *listConfig = config[listID];
        if (listConfig && listConfig[iconID]) {
            return [listConfig[iconID] unsignedLongLongValue]; // 强行返回我们保存的坐标
        }
    }
    return %orig;
}

// 【强制防吸附】：无论系统觉得放哪里合适，强行告诉它：手指松开在哪，就放在哪！
- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index {
    return index;
}

- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfo:(id)info {
    return index;
}

- (unsigned long long)bestGridCellIndexForInsertingIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options {
    return index;
}


// 【拦截写入 - 移动】：移动图标后，保存到我们的 Plist
- (id)moveContainedIcon:(id)icon toGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    
    if (listID && iconID && index != NSNotFound) {
        NSMutableDictionary *config = GetGridConfig();
        NSMutableDictionary *listConfig = [config[listID] mutableCopy] ?: [NSMutableDictionary dictionary];
        
        listConfig[iconID] = @(index);
        config[listID] = listConfig;
        SaveGridConfig(config);
        
        // 顺便喂给系统原生字典一口，保持内存同步
        if ([self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
            [self setFixedLocation:index forIcon:icon];
        }
    }
    return result;
}

// 【拦截写入 - 插入】：新增或从其他页面拖入时，保存到我们的 Plist
- (id)insertIcon:(id)icon atGridCellIndex:(unsigned long long)index gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    id result = %orig;
    
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    
    if (listID && iconID && index != NSNotFound) {
        NSMutableDictionary *config = GetGridConfig();
        NSMutableDictionary *listConfig = [config[listID] mutableCopy] ?: [NSMutableDictionary dictionary];
        
        listConfig[iconID] = @(index);
        config[listID] = listConfig;
        SaveGridConfig(config);
        
        if ([self respondsToSelector:@selector(setFixedLocation:forIcon:)]) {
            [self setFixedLocation:index forIcon:icon];
        }
    }
    return result;
}

// 【拦截写入 - 删除】：从桌面移除图标时，同步清理 Plist 中的记录
- (void)removeIcon:(id)icon gridCellInfoOptions:(unsigned long long)options mutationOptions:(unsigned long long)mutOptions {
    %orig;
    
    NSString *listID = [self uniqueIdentifier];
    NSString *iconID = GetIconID(icon);
    
    if (listID && iconID) {
        NSMutableDictionary *config = GetGridConfig();
        NSMutableDictionary *listConfig = [config[listID] mutableCopy];
        if (listConfig) {
            [listConfig removeObjectForKey:iconID];
            config[listID] = listConfig;
            SaveGridConfig(config);
        }
    }
}

%end
