// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart' as d;
import 'package:flutter/material.dart';
import 'package:social_media_app/class/UserDataClass.dart';
import 'package:social_media_app/class/UserDataNotifier.dart';
import 'package:social_media_app/class/UserSocialClass.dart';
import 'package:social_media_app/class/UserSocialNotifier.dart';
import 'package:social_media_app/redux/reduxLibrary.dart';
import 'package:social_media_app/styles/AppStyles.dart';
import 'package:social_media_app/appdata/GlobalLibrary.dart';
import 'caching/sqfliteConfiguration.dart';
import 'custom/CustomPagination.dart';
import 'custom/CustomUserDataWidget.dart';

class SearchedUsersWidget extends StatelessWidget {
  final String searchedText;
  final BuildContext absorberContext;
  const SearchedUsersWidget({super.key, required this.searchedText, required this.absorberContext});

  @override
  Widget build(BuildContext context) {
    return _SearchedUsersWidgetStateful(searchedText: searchedText, absorberContext: absorberContext);
  }
}

class _SearchedUsersWidgetStateful extends StatefulWidget {
  final String searchedText;
  final BuildContext absorberContext;
  const _SearchedUsersWidgetStateful({required this.searchedText, required this.absorberContext});

  @override
  State<_SearchedUsersWidgetStateful> createState() => _SearchedUsersWidgetStatefulState();
}

var dio = d.Dio();

class _SearchedUsersWidgetStatefulState extends State<_SearchedUsersWidgetStateful> with AutomaticKeepAliveClientMixin{
  final ScrollController _scrollController = ScrollController();
  ValueNotifier<bool> displayFloatingBtn = ValueNotifier(false);
  late String searchedText;
  ValueNotifier<bool> isLoading = ValueNotifier(false);
  ValueNotifier<List<String>> users = ValueNotifier([]);
  ValueNotifier<LoadingStatus> loadingUsersStatus = ValueNotifier(LoadingStatus.loaded);
  ValueNotifier<int> totalUsersLength = ValueNotifier(usersServerFetchLimit);
  

  @override
  void initState(){
    super.initState();
    searchedText = widget.searchedText;
    runDelay(() async => fetchSearchedUsers(users.value.length, false, false), actionDelayTime);
    _scrollController.addListener(() {
      if(mounted){
        if(_scrollController.position.pixels > animateToTopMinHeight){
          if(!displayFloatingBtn.value){
            displayFloatingBtn.value = true;
          }
        }else{
          if(displayFloatingBtn.value){
            displayFloatingBtn.value = false;
          }
        }
      }
    });
  }

  @override void dispose(){
    super.dispose();
    isLoading.dispose();
    _scrollController.dispose();
    displayFloatingBtn.dispose();
    users.dispose();
    loadingUsersStatus.dispose();
    totalUsersLength.dispose();
  }

  Future<void> fetchSearchedUsers(int currentUsersLength, bool isRefreshing, bool isPaginating) async{
    try {
      if(mounted){
        isLoading.value = true;
        String stringified = '';
        d.Response res;
        if(!isPaginating){
          stringified = jsonEncode({
            'searchedText': widget.searchedText,
            'currentID': fetchReduxDatabase().currentID,
            'currentLength': currentUsersLength,
            'paginationLimit': usersPaginationLimit,
            'maxFetchLimit': usersServerFetchLimit
          });
          res = await dio.get('$serverDomainAddress/users/fetchSearchedUsers', data: stringified);
        }else{
          List paginatedSearchedUsers = await DatabaseHelper().fetchPaginatedSearchedUsers(currentUsersLength, usersPaginationLimit);
          stringified = jsonEncode({
            'searchedText': widget.searchedText,
            'searchedUsersEncoded': jsonEncode(paginatedSearchedUsers),
            'currentID': fetchReduxDatabase().currentID,
            'currentLength': currentUsersLength,
            'paginationLimit': usersPaginationLimit,
            'maxFetchLimit': usersServerFetchLimit
          });
          res = await dio.get('$serverDomainAddress/users/fetchSearchedUsersPagination', data: stringified);
        }
        if(res.data.isNotEmpty){
          if(res.data['message'] == 'Successfully fetched data'){
            if(!isPaginating){
              List searchedUsers = res.data['searchedUsers'];
              await DatabaseHelper().replaceAllSearchedUsers(searchedUsers);
            }
            List userProfileDataList = res.data['usersProfileData'];
            List usersSocialsDatasList = res.data['usersSocialsData'];
            if(isRefreshing && mounted){
              users.value = [];
            }
            if(!isPaginating && mounted){
              totalUsersLength.value = min(res.data['totalUsersLength'], usersServerFetchLimit);
            }
            for(int i = 0; i < userProfileDataList.length; i++){
              Map userProfileData = userProfileDataList[i];
              UserDataClass userDataClass = UserDataClass.fromMap(userProfileData);
              UserSocialClass userSocialClass = UserSocialClass.fromMap(usersSocialsDatasList[i]);
              if(mounted){
                updateUserData(userDataClass, context);
                updateUserSocials(userDataClass, userSocialClass, context);
                if(users.value.length < totalUsersLength.value){
                  users.value = [...users.value, userProfileData['user_id']];
                }
              }
            }
          }
          if(mounted){
            isLoading.value = false;
          }
        }
      }
    } on Exception catch (e) {
      doSomethingWithException(e);
    }
  }

  Future<void> loadMoreUsers() async{
    try {
      if(mounted){
        loadingUsersStatus.value = LoadingStatus.loading;
        Timer.periodic(const Duration(milliseconds: 1500), (Timer timer) async{
          timer.cancel();
          await fetchSearchedUsers(users.value.length, false, true);
          if(mounted){
            loadingUsersStatus.value = LoadingStatus.loaded;
          }
        });
      }
    } on Exception catch (e) {
      doSomethingWithException(e);
    }
  }

  Future<void> refresh() async{
    fetchSearchedUsers(0, true, false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
     return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            top: false,
            bottom: false,
            child: Builder(
              builder: (BuildContext context) {
                return StoreConnector<AppState, ValueNotifier<Map<String, UserDataNotifier>>>(
                  converter: (store) => store.state.usersDatasNotifiers,
                  builder: (context, ValueNotifier<Map<String, UserDataNotifier>> usersDatasNotifiers){
                    return StoreConnector<AppState, ValueNotifier<Map<String, UserSocialNotifier>>>(
                      converter: (store) => store.state.usersSocialsNotifiers,
                      builder: (context, ValueNotifier<Map<String, UserSocialNotifier>> usersSocialsNotifiers){
                        return ValueListenableBuilder(
                          valueListenable: loadingUsersStatus,
                          builder: (context, loadingStatusValue, child){
                            return ValueListenableBuilder(
                              valueListenable: totalUsersLength,
                              builder: (context, totalUsersLengthValue, child){
                                return ValueListenableBuilder(
                                  valueListenable: users,
                                  builder: ((context, users, child) {
                                    return LoadMoreBottom(
                                      addBottomSpace: users.length < totalUsersLength.value,
                                      loadMore: () async{
                                        if(users.length < totalUsersLength.value){
                                          await loadMoreUsers();
                                        }
                                      },
                                      status: loadingStatusValue,
                                      refresh: refresh,
                                      child: CustomScrollView(
                                        controller: _scrollController,
                                        physics: const AlwaysScrollableScrollPhysics(),
                                        slivers: <Widget>[
                                          SliverOverlapInjector(
                                            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)
                                          ),
                                          SliverList(delegate: SliverChildBuilderDelegate(
                                            childCount: users.length, 
                                            (context, index) {
                                              if(fetchReduxDatabase().usersDatasNotifiers.value[users[index]] != null){
                                                return ValueListenableBuilder(
                                                  valueListenable: fetchReduxDatabase().usersDatasNotifiers.value[users[index]]!.notifier, 
                                                  builder: ((context, userData, child) {
                                                    return ValueListenableBuilder(
                                                      valueListenable: fetchReduxDatabase().usersSocialsNotifiers.value[users[index]]!.notifier, 
                                                      builder: ((context, userSocial, child) {
                                                        return CustomUserDataWidget(
                                                          userData: userData,
                                                          userSocials: userSocial,
                                                          userDisplayType: UserDisplayType.searchedUsers,
                                                          profilePageUserID: null,
                                                          isLiked: null,
                                                          isBookmarked: null,
                                                          key: UniqueKey()
                                                        );
                                                      })
                                                    );
                                                  })
                                                );
                                              }
                                              return Container();  
                                            }
                                          ))                                    
                                        ]
                                      )
                                    );
                                  })
                                );
                              }
                            );
                          }
                        );
                      }
                    );
                  }
                );
              }
            )
          ),
          ValueListenableBuilder(
            valueListenable: isLoading,
            builder: ((context, isLoadingValue, child) {
              if(isLoadingValue){
                return loadingPageWidget();
              }
              return Container();
            })
          )
        ]
      ),
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: displayFloatingBtn,
        builder: (BuildContext context, bool visible, Widget? child) {
          return Visibility(
            visible: visible,
            child: FloatingActionButton( 
              heroTag: UniqueKey(),
              onPressed: () {  
                _scrollController.animateTo(
                  0,
                  duration: const Duration(milliseconds: 10),
                  curve:Curves.fastOutSlowIn
                );
              },
              child: const Icon(Icons.arrow_upward),
            )
          );
        }
      )
    );
  }
  
  @override
  bool get wantKeepAlive => true;
}